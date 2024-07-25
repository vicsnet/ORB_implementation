use starknet::{ContractAddress};
#[starknet::interface]
trait IERC20<T> {
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn allowance(self: @T, owner: ContractAddress, spender: ContractAddress) -> u256;

    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;

    fn transfer_from(
        ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait ORBPond<TContractState> {
    fn get_registry(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait ORB<TContractState> {
    fn get_pond_address(self: @TContractState) -> ContractAddress;
    fn main_keeper(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait OrbInvocationRegistry<TContractState> {
    fn get_invocations(
        self: @TContractState, orb_address: ContractAddress, invocation_id_: u256
    ) -> (ByteArray, ContractAddress);
}
#[starknet::interface]
trait OrbInvocationTipJarTrait<TContractState> {
    fn tip_invocation(
        ref self: TContractState,
        orb_address: ContractAddress,
        token_address: ContractAddress,
        invocation_hash_: ByteArray,
        tip_amount: u256,
    );

    fn claim_tips_for_invocation(
        ref self: TContractState,
        orb_address: ContractAddress,
        invocation_id_: u256,
        minimum_tip_total: u256,
        token_address: ContractAddress,
    );

    fn withdraw_tip(
        ref self: TContractState,
        invocation_hash: ByteArray,
        orb_address: ContractAddress,
        token_address: ContractAddress
    );

    fn withdraw_tips(
        ref self: TContractState,
        orbs_address: Array<ContractAddress>,
        content_hashes_: Array<ByteArray>,
        token_address: ContractAddress
    );

    fn withdraw_platform_funds(ref self: TContractState, token_address: ContractAddress);

    fn set_minimum_tip_value(
        ref self: TContractState, orb_address: ContractAddress, minimum_tip_value: u256
    );
}
#[starknet::contract]
mod ORBInvocationTipJar {
    use core::starknet::event::EventEmitter;
    use core::clone::Clone;
    use core::box::BoxTrait;
    use core::array::ArrayTrait;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use core::num::traits::Zero;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::{poseidon::PoseidonTrait};
    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, ORBPondDispatcher, ORBPondDispatcherTrait,
        ORBDispatcher, ORBDispatcherTrait, OrbInvocationRegistryDispatcher,
        OrbInvocationRegistryDispatcherTrait
    };
    const FEE_DENOMINATOR: u256 = 100;
    #[storage]
    struct Storage {
        // the minimum tip value for a given Orb
        minimum_tips: LegacyMap::<ContractAddress, u256>,
        // Whether a certain invocation's tips have been claimed: invocationId starts from 1
        // felt252 is the hash of invocationhash and orb address
        claimed_invocations: LegacyMap::<felt252, u256>,
        // the sum of all tips for a given invocation
        // felt252 is the hash of orb_address and ByteArray
        total_tips: LegacyMap::<felt252, u256>,
        // The sum of all tips for a given invocation by a given tipper
        // contract address is the address of the Orb, felt252 is the hash of the tipper address and byteArray of the invocation hash, u256 is the tipped amount.
        tipper_tips: LegacyMap::<(ContractAddress, felt252), u256>,
        // Fund allocated for the Orb Land platform, `withdrawable to platformAddress`
        platform_funds: u256,
        // Orb Land Revenue fee numerator
        platform_fee: u256,
        // Orbland Revenue Address
        platform_address: ContractAddress,
    }

    #[derive(Drop, Hash)]
    struct HashData {
        orb_address: ContractAddress,
        invocation_hash: felt252,
    }

    #[derive(Serde, Drop)]
    struct Hash_byte {
        hash: ByteArray,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TipDeposit: TipDeposit,
        TipsClaim: TipsClaim,
        MinimumTipValue: MinimumTipValue
    }
    #[derive(Drop, starknet::Event)]
    struct TipDeposit {
        orb_address: ContractAddress,
        invocation_hash: ByteArray,
        tipper: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    struct TipsClaim {
        orb_address: ContractAddress,
        content_hash: ByteArray,
        invoker: ContractAddress,
        invoker_portion: u256
    }
    #[derive(Drop, starknet::Event)]
    struct MinimumTipValue {
        orb_address: ContractAddress,
        previous_tip: u256,
        minimum_tip: u256
    }

    impl OrbInvocationTipJar of super::OrbInvocationTipJarTrait<ContractState> {
        /// @notice  Tips a specific invocation content hash on an Orb 
        /// @dev Emits 'TipDeposit'
        /// @param orb_address The address of the Orb
        /// @param invocation_hash_ The invocation content hash
        fn tip_invocation(
            ref self: ContractState,
            orb_address: ContractAddress,
            token_address: ContractAddress,
            invocation_hash_: ByteArray,
            tip_amount: u256,
        ) {
            let caller = get_caller_address();
            let address_this = get_contract_address();
            let minimum_tip_ = self.minimum_tips.read(orb_address);
            assert(tip_amount >= minimum_tip_, 'INSUFFICIENT TIP');
            let hash_ = invocation_hash_.clone();
            let my_hash_data_ = hash_.clone();
            let hash_data_ = self.hash_(orb_address, hash_);
            assert(self.claimed_invocations.read(hash_data_) <= 0, 'INVOCATION_CLAIMED');
            let tipper_hash_ = self.hash_(caller, invocation_hash_);

            let amount_ = self.total_tips.read(hash_data_) + tip_amount;
            assert(
                IERC20Dispatcher { contract_address: token_address }
                    .balance_of(caller) > tip_amount,
                'INSUFFICIENT_FUND'
            );
            IERC20Dispatcher { contract_address: token_address }
                .transfer_from(caller, address_this, tip_amount);
            self.total_tips.write(hash_data_, amount_);
            self
                .tipper_tips
                .write(
                    (orb_address, tipper_hash_),
                    self.tipper_tips.read((orb_address, tipper_hash_)) + tip_amount
                );
            self
                .emit(
                    TipDeposit {
                        orb_address: orb_address, invocation_hash: my_hash_data_, tipper: caller,
                    }
                )
        }
        /// @notice Claim all tips for a given sugested invocation
        /// @dev Emits 'TipsClaim'
        /// @param orb_address The address of the Orb
        /// @param invocation_id_ The invocation id to check
        /// @param minimum_tip_total the minimu tipvalue to claim
        fn claim_tips_for_invocation(
            ref self: ContractState,
            orb_address: ContractAddress,
            invocation_id_: u256,
            minimum_tip_total: u256,
            token_address: ContractAddress,
        ) {
            let pond_address_ = ORBDispatcher { contract_address: orb_address }.get_pond_address();
            let invocation_registry_address = ORBPondDispatcher { contract_address: pond_address_ }
                .get_registry();
            let (content_hash, invoker) = OrbInvocationRegistryDispatcher {
                contract_address: invocation_registry_address
            }
                .get_invocations(orb_address, invocation_id_);
            let content_hash_data = content_hash.clone();

            assert(content_hash.len() > 0, 'INVOCATION_NOT_INVOKED');
            let hash_felt = self.hash_(orb_address, content_hash);
            let total_claimable_tips = self.total_tips.read(hash_felt);
            assert(total_claimable_tips > minimum_tip_total, 'INSUFICIENT_CLAIMABLE_TIPS');
            assert(self.claimed_invocations.read(hash_felt) <= 0, 'INVOCATION_CLAIMED');
            let platform_portion = (total_claimable_tips * self.platform_fee.read())
                / FEE_DENOMINATOR;
            let invoker_portion = total_claimable_tips - platform_portion;

            self.claimed_invocations.write(hash_felt, invocation_id_);
            self.platform_funds.write(self.platform_funds.read() + platform_portion);
            IERC20Dispatcher { contract_address: token_address }.transfer(invoker, invoker_portion);
            self
                .emit(
                    TipsClaim {
                        orb_address: orb_address,
                        content_hash: content_hash_data,
                        invoker: invoker,
                        invoker_portion: invoker_portion
                    }
                );
        }

        /// @notice Withdraws all tips from a given list of Orbs and invocations.
        /// @param orb_address Address of the Orb
        /// @param invocation_hash Hash of the Content 
        /// @param token_address Address of the accepted token 
        fn withdraw_tip(
            ref self: ContractState,
            invocation_hash: ByteArray,
            orb_address: ContractAddress,
            token_address: ContractAddress
        ) {
            self.withdraw_tip_(invocation_hash, get_caller_address(), orb_address, token_address);
        }

        /// @notice Withdraws all tips from a given list of Orbs and invocations.
        /// @param orb_address Array Address of the Orb
        /// @param invocation_hash Array Hash of the Content 
        /// @param token_address Address of the accepted token 
        fn withdraw_tips(
            ref self: ContractState,
            orbs_address: Array<ContractAddress>,
            content_hashes_: Array<ByteArray>,
            token_address: ContractAddress
        ) {
            assert(orbs_address.len() == content_hashes_.len(), 'UNEVEN_ARRAY');
            let mut i = 0;
            while i < orbs_address
                .len() {
                    let orb_address = orbs_address.at(i); // Safe to unwrap as we are within bounds
                    let content_hash_boxed = content_hashes_
                        .at(i)
                        .clone(); // Safe to unwrap as we are within bounds

                    let content_hash = content_hash_boxed;

                    self
                        .withdraw_tip_(
                            content_hash, get_caller_address(), *orb_address, token_address
                        );

                    i = i + 1;
                };
        }
        /// @notice  Withdraws all funds set aside as the platform fee. Can be called by anyone.
        fn withdraw_platform_funds(ref self: ContractState, token_address: ContractAddress) {
            let platform_fund_ = self.platform_funds.read();
            assert(platform_fund_ > 0, 'NO_AVAILABLE_FUND');
            IERC20Dispatcher { contract_address: token_address }
                .transfer(self.platform_address.read(), platform_fund_);
        }

        /// @notice  Sets the minimum tip value for a given Orb.
        /// @dev Emits 'MinimumTipValue'
        /// @param   orb_address The address of the Orb
        /// @param   minimum_tip_value  The minimum tip value
        fn set_minimum_tip_value(
            ref self: ContractState, orb_address: ContractAddress, minimum_tip_value: u256
        ) {
            let main_keeper_ = ORBDispatcher { contract_address: orb_address }.main_keeper();
            assert(main_keeper_ == get_caller_address(), 'NOT_MAIN_KEEPER');
            let previous_tip = self.minimum_tips.read(orb_address);
            self.minimum_tips.write(orb_address, minimum_tip_value);
            self
                .emit(
                    MinimumTipValue {
                        orb_address: orb_address,
                        previous_tip: previous_tip,
                        minimum_tip: minimum_tip_value
                    }
                );
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        /// @notice Withdraws all tips from a given list of Orbs and invocations.
        /// @param orb_address Address of the Orb
        /// @param caller_address Address of the caller
        /// @param invocation_hash Hash of the Content 
        /// @param token_address Address of the accepted token 
        fn withdraw_tip_(
            ref self: ContractState,
            content_hash: ByteArray,
            caller_address_: ContractAddress,
            orb_address: ContractAddress,
            token_address: ContractAddress
        ) {
            let new_hash = content_hash.clone();
            let hash_data_tip = self.hash_(caller_address_, content_hash);
            let tip_value = self.tipper_tips.read((orb_address, hash_data_tip));
            let hash_data = self.hash_(orb_address, new_hash);
            assert(tip_value > 0, 'TIP_NOT_FOUND');
            assert(self.claimed_invocations.read(hash_data) <= 0, 'INVOCATION_CLAIMED');
            self.total_tips.write(hash_data, self.total_tips.read(hash_data) - tip_value);
            self.tipper_tips.write((orb_address, hash_data_tip), 0);
            IERC20Dispatcher { contract_address: token_address }
                .transfer(caller_address_, tip_value);
        }

        /// @notice convert ByteArray to felt252 .
        fn byte_array_to_felt252(ref self: ContractState, byte_array: ByteArray) -> felt252 {
            let mut result: felt252 = 0;
            let my_hash = Hash_byte { hash: byte_array };
            let mut i = 0;
            let mut constructor_calldata = ArrayTrait::new();
            my_hash.serialize(ref constructor_calldata);

            while i < constructor_calldata
                .len() {
                    let a_ = constructor_calldata.at(i);
                    result += *a_;
                };

            result
        }


        fn hash_(
            ref self: ContractState, orb_address: ContractAddress, invocation_hash: ByteArray
        ) -> felt252 {
            let hashed_data = self.byte_array_to_felt252(invocation_hash);
            let my_hashed_data = HashData { orb_address, invocation_hash: hashed_data };

            let poseidon_hash = PoseidonTrait::new().update_with(my_hashed_data).finalize();
            poseidon_hash
        }
    }
}
