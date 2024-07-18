use starknet::ContractAddress;
// ERC721 interface
#[starknet::interface]
trait IERC_721<TContractState> {
    fn balance_of(self: @TContractState, owner_: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id_: u256) -> ContractAddress;
    fn safe_transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn approve(ref self: TContractState, approved: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn get_apporved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner_: ContractAddress, operator: ContractAddress
    ) -> bool;
}

#[starknet::interface]
trait IERC_165<TContractState> {
    fn suports_interfaace(self: @TContractState, interface_id: ByteArray) -> bool;
}

#[starknet::interface]
trait IERC721_token_receiver<TContractState> {
    fn on_ERC721_received(
        ref self: TContractState,
        operator: ContractAddress,
        from: ContractAddress,
        token_id: u256,
        data: ByteArray
    ) -> ByteArray;
}

#[starknet::interface]
trait IERC721_metadata<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn token_uri(self: @TContractState) -> felt252;
}
#[starknet::interface]
trait IERC20<T> {
    fn name(self: @T) -> felt252;

    fn symbol(self: @T) -> felt252;

    fn decimals(self: @T) -> u8;

    fn total_supply(self: @T) -> u256;

    fn balance_of(self: @T, account: ContractAddress) -> u256;

    fn allowance(self: @T, owner: ContractAddress, spender: ContractAddress) -> u256;

    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;

    fn transfer_from(
        ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
}
#[starknet::interface]
trait OrbInvocation<TContractState> {
    fn prevent_violation(
        self: @TContractState, contract_address: ContractAddress, owner_: ContractAddress
    ) -> bool;
    fn prevent_violation_owner(
        self: @TContractState, contract_address: ContractAddress, owner_: ContractAddress
    ) -> bool;
}

#[starknet::contract]
mod ERC721 {
    use core::starknet::event::EventEmitter;
    use starknet::{
        ContractAddress, get_caller_address, storage_access::StorageBaseAddress,
        get_contract_address, get_block_timestamp, contract_address_const
    };
    use core::num::traits::Zero;
    use super::{
        IERC20Dispatcher, IERC20DispatcherTrait, OrbInvocationDispatcher,
        OrbInvocationDispatcherTrait
    };
    // Max_Supply of NFT to prevent over Fractionalization
    const MAX_SUPPLY: u256 = 5;
    // weights 
    //Equivalent to 0.4
    const WEIGHT_USAGE_LEVEL: u256 = 4;
    //Equivalent to 0.3
    const WEIGHT_SUBSCRIPTION_DEMAND: u256 = 3;
    //Equivalent to 0.3
    const WEIGHT_USER_SATISFACTION: u256 = 3;

    // Maximum cooldown duration is 10 years 
    const COOLDOWN_MAXIMUM_DURATION: u256 = 3650;

    //storage
    #[storage]
    struct Storage {
        name: felt252,
        symbol: felt252,
        token_URI: felt252,
        owner: ContractAddress,
        token_id: u256,
        // Honored Until: time stamp until which the Orb Oath is honored for the keeper
        honored_until: u256,
        // List the Orb: Determine if ORb fraction can be purchased
        orb_status: bool,
        // Response Period: time period in which the keeper promises to repond to an invocation.
        // Penalty: premium price will reduce if not fufiled
        response_period: u256,
        // totalSupply of the fractioned NFT token
        total_supply: u256,
        // fractioned token bought
        token_owned: u256,
        // Fractioned token Owned last id
        last_token_id: u256,
        // total price of the Orb
        price: u256,
        // max time to hold token before resubscription this should be calculated in days assuming 10 days 10 * 24 * 60 * 60
        purchase_period: u256,
        // cooldown period assuming 7 days 7 *24*60*60
        cooldown: u256,
        // flagging period
        flagging_period: u256,
        // maximum length for invocation clear text
        clear_text_maximum_length: u256,
        // owners: LegacyMap::<u256, ContractAddress>,
        // mapping address this to the parameters
        parameters_data: LegacyMap::<ContractAddress, Parameters>,
        // mapping to monitor usage  
        parameters_monitor: LegacyMap::<u256, MonitorParameters>,
        // fractioned balance of the token holder
        fractioned_balances: LegacyMap::<ContractAddress, u256>,
        // fractioned token id
        fractioned_token_id_owner: LegacyMap::<u256, ContractAddress>,
        // unit of fractioned token attached to an id
        fractioned_token_id: LegacyMap::<u256, u256>,
        // token owned by individual: deposited token or rewards
        balances: LegacyMap::<ContractAddress, u256>,
        // Subscription time stamp: showing current period of subscrition.
        // mapping of tokenId to block.timestamp
        subscription_time: LegacyMap::<u256, u256>,
        // Monitor last invocation time 
        last_invocation: LegacyMap::<u256, u256>,
        //Address of the `OrbPond` that deployed this Orb
        pond: ContractAddress,
        token_approvals: LegacyMap::<u256, ContractAddress>,
        operator_approvals: LegacyMap::<(ContractAddress, ContractAddress), bool>,
    }
    // saved parameters to determine premium price
    #[derive(Drop, Serde, starknet::Store)]
    struct Parameters {
        usage_level: u256,
        user_satisfaction: u256,
        subscription_demand: u256,
    }
    // Struct to monitor usae of the fractioned Orb 
    #[derive(Drop, Serde, starknet::Store)]
    struct MonitorParameters {
        usage_level: u256,
        user_satisfaction: u256,
    }

    // Event

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        transfer: Transfer,
        approval: Approval,
        approval_for_all: Approval_for_all,
        OathSwearing: OathSwearing,
        HonoredUntilUpdate: HonoredUntilUpdate,
        CooldownUpdate: CooldownUpdate,
        CleartextMaximumLengthUpdate: CleartextMaximumLengthUpdate,
        BuyOrb: BuyOrb,
        NonActivePurchase: NonActivePurchase,
        TokenDeposit: TokenDeposit,
        WithdrawFund: WithdrawFund,
        OrbReliquish: OrbReliquish,
        LastInvocation: LastInvocation,
        ForeClosure: ForeClosure
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        approved: ContractAddress,
        token_id: u256
    }


    #[derive(Drop, starknet::Event)]
    struct Approval_for_all {
        #[key]
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool
    }

    #[derive(Drop, starknet::Event)]
    struct OathSwearing {
        #[key]
        oath_hash: ByteArray,
        honored_until: u256,
        response_period: u256
    }

    #[derive(Drop, starknet::Event)]
    struct HonoredUntilUpdate {
        #[key]
        previous_honored_until: u256,
        new_honored_until: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct CooldownUpdate {
        #[key]
        previous_cooldown: u256,
        new_cooldown: u256,
        previous_flagging_period: u256,
        new_flagging_period: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct CleartextMaximumLengthUpdate {
        #[key]
        previous_cleartext_maximum_length: u256,
        new_leartext_maximum_length: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct BuyOrb {
        #[key]
        buyer_address: ContractAddress,
        amount_: u256,
        fractioned_unit_: u256,
        token_id: u256
    }
    #[derive(Drop, starknet::Event)]
    struct NonActivePurchase {
        #[key]
        new_owner: ContractAddress,
        previous_owner: ContractAddress,
        amount_: u256,
        token_id: u256
    }
    #[derive(Drop, starknet::Event)]
    struct TokenDeposit {
        #[key]
        owner: ContractAddress,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct WithdrawFund {
        #[key]
        amount: u256,
        owner: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    struct OrbReliquish {
        #[key]
        orb_owner: ContractAddress,
        token_id: u256
    }
    #[derive(Drop, starknet::Event)]
    struct LastInvocation {
        #[key]
        token_id: u256,
        invocation_time: u256
    }
    #[derive(Drop, starknet::Event)]
    struct ForeClosure {
        #[key]
        token_id: u256
    }
    /// @dev when deployed Contract mint the main token to the deployer
    /// This token represent the major Orb
    /// The Fractioned unit of the main token is transfered to the contract addess
    /// owner is been set to the deployer of the contract tx.origin
    ///  @param name_ Orb name used in ERC721 metadata
    ///  @param symbol_ Orb symbol used in ERC721 metadata
    ///  @param total_supply_ Orb fractioned total number
    ///  @param token_uri_ Initial value for tokenURI JSONs
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name_: felt252,
        symbol_: felt252,
        total_supply_: u256,
        token_uri_: felt252,
        owner_: ContractAddress
    ) {
        assert(total_supply_ <= MAX_SUPPLY, 'SUPPLY_EXCEED_MAX');
        assert(total_supply_ >= 1, 'INCREASE_SUPPLY');
        self.name.write(name_);
        self.symbol.write(symbol_);
        self.total_supply.write(total_supply_);
        self.token_URI.write(token_uri_);
        self.owner.write(owner_);
        self.pond.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl ERC721_metadata of super::IERC721_metadata<ContractState> {
        /// @dev returns Orb name used in ERC721 metadata
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }
        /// @dev returns Orb symbol used in ERC721 metadata
        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }
        /// @dev returns tokenURI JSONs
        fn token_uri(self: @ContractState) -> felt252 {
            self.token_URI.read()
        }
    }

    #[abi(embed_v0)]
    impl ERC721 of super::IERC_721<ContractState> {
        /// @notice this function Returns 0 for non main keeper address i.e the address  that deployed the contract
        /// @param owner_ Address to check owner for
        fn balance_of(self: @ContractState, owner_: ContractAddress) -> u256 {
            if (owner_ != self.owner.read()) {
                0
            } else {
                1
            }
        }

        /// @notice  returns Address of the token owner
        /// @param token_id_ Id to check owner for
        fn owner_of(self: @ContractState, token_id_: u256) -> ContractAddress {
            self.fractioned_token_id_owner.read(token_id_)
        }
        /// @notice this function is not supported
        fn safe_transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            assert(from.is_zero(), 'NOT_SUPPORTED');
            assert(!from.is_zero(), 'NOT_SUPPORTED');
        }
        /// @notice this function is not supported
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            assert(from.is_zero(), 'NOT_SUPPORTED');
            assert(!from.is_zero(), 'NOT_SUPPORTED');
        }
        /// @notice function is not supported
        fn approve(ref self: ContractState, approved: ContractAddress, token_id: u256) {
            assert(approved.is_zero(), 'NOT_SUPPORTED');
            assert(!approved.is_zero(), 'NOT_SUPPORTED');
        }
        /// @notice function is not supported
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            assert(operator.is_zero(), 'NOT_SUPPORTED');
            assert(!operator.is_zero(), 'NOT_SUPPORTED');
        }
        /// @notice function is not supported
        fn get_apporved(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(token_id == 0, 'NOT_SUPPORTED');
            assert(token_id != 0, 'NOT_SUPPORTED');
            get_contract_address()
        }
        ///  @notice function is not supported
        fn is_approved_for_all(
            self: @ContractState, owner_: ContractAddress, operator: ContractAddress
        ) -> bool {
            assert(operator.is_zero(), 'NOT_SUPPORTED');
            assert(!operator.is_zero(), 'NOT_SUPPORTED');
            false
        }
    }
    /// @notice get the total fractioned supply
    /// @return Returns total supply of the Fractioned Orb 
    #[external(v0)]
    fn get_total_supply(self: @ContractState) -> u256 {
        self.total_supply.read()
    }
    /// @notice Checks the tokenbalance of the caller on the contract
    /// @param owner_ Address to check the balance for
    /// @return the balance of the Owner_ Address
    #[external(v0)]
    fn token_balance_of(self: @ContractState, owner_: ContractAddress) -> u256 {
        self.balances.read(owner_)
    }
    /// @notice set the total Orb price
    /// @param price_ the Price of the total fractioned Orb
    #[external(v0)]
    fn set_price(ref self: ContractState, price_: u256) {
        let caller = get_caller_address();
        self.only_owner(caller);
        self.set_price_(price_);
    }
    /// @notice activate the Orb
    #[external(v0)]
    fn start_orb(ref self: ContractState) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        self.orb_status.write(true);
    }

    /// @notice Allows Swearing of the Orb Oath and set a new `honored` date. function can only be called by the Orb creator
    /// @dev Emit `Oath Swearing`
    /// @param oath_hash Hash
    /// @param new_honored_until Date untill which the Orb creator will honor the Oath of the fractioned Orb keeper
    /// @param new_response_period Duration within which the Orb creator promises to respond to invocation
    #[external(v0)]
    fn swear_oath(
        ref self: ContractState,
        oath_hash: ByteArray,
        new_honored_until: u256,
        new_response_period: u256
    ) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(self.honored_until.read() == 0, 'HONORED_DATE_DISAPPROVED');
        assert(new_response_period > 0, 'INCREASE_RESPONSE_PERIOD');
        self.honored_until.write(new_honored_until);
        self.response_period.write(new_response_period);
        // emmit oat_hash as event 
        self
            .emit(
                OathSwearing {
                    oath_hash,
                    honored_until: new_honored_until,
                    response_period: new_response_period
                }
            );
    }

    /// @notice Allows the Orb creator to extend the honoredUntil date
    /// @dev Emits `HonoredUntilUpdate`
    /// @param new_honored_until Date until which the Orb creator will honor the Oath for the Orb keeper. must be greater than the current

    #[external(v0)]
    fn extend_honored_until(ref self: ContractState, new_honored_until: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_honored_until > self.honored_until.read(), 'HONORED_DATE_DISAPPROVED');
        self.honored_until.write(new_honored_until);
        self
            .emit(
                HonoredUntilUpdate {
                    previous_honored_until: self.honored_until.read(),
                    new_honored_until: new_honored_until,
                }
            );
    }
    /// @notice Allows the Orb creator to set the new cooldown duration period
    /// @dev Emits `CooldownUpdate`
    /// @param new_cooldown New cooldown in seconds. cannot be longer than `COOLDOWN_MAXIMUM_DURATION`
    /// @param new_flagging_period New flagging period in seconds
    #[external(v0)]
    fn set_cool_down(ref self: ContractState, new_cooldown: u256, new_flagging_period: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_cooldown < COOLDOWN_MAXIMUM_DURATION, 'COOLDOWN_EXCEED_DURATION');
        self.cooldown.write(new_cooldown);
        self.flagging_period.write(new_flagging_period);
        self
            .emit(
                CooldownUpdate {
                    previous_cooldown: self.cooldown.read(),
                    new_cooldown: new_cooldown,
                    previous_flagging_period: self.flagging_period.read(),
                    new_flagging_period: new_flagging_period,
                }
            );
    }

    /// @notice Allows the Orb creator to set the new cleartext maximum length.
    /// @dev Emit `CleartextMaximumLengthUPdate`
    /// @param new_clear_text new clear text maximum length. Cannot be 0.
    #[external(v0)]
    fn set_clear_text_maximum_length(ref self: ContractState, new_clear_text: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_clear_text > 0, 'INVALID_TEXT_MAXIMUM_LENGTH');
        self.clear_text_maximum_length.write(new_clear_text);
        self
            .emit(
                CleartextMaximumLengthUpdate {
                    previous_cleartext_maximum_length: self.clear_text_maximum_length.read(),
                    new_leartext_maximum_length: new_clear_text,
                }
            );
    }

    /// @notice buy a Fractioned part of the Orb
    /// @dev Emits 'BuyOrb'
    /// @param buyer_address address of the buyer
    /// @param amount_ the value of the fractioned orb
    /// @param token_address_ address of the payment token
    /// @param fractioned_unit_ tunit of the token to be purchased
    #[external(v0)]
    fn buy_orb(
        ref self: ContractState,
        buyer_address: ContractAddress,
        amount_: u256,
        token_address_: ContractAddress,
        fractioned_unit_: u256
    ) {
        assert(self.token_owned.read() <= self.total_supply.read(), 'NO_AVAILABLE_TOKEN');
        assert(
            fractioned_unit_ + self.token_owned.read() <= self.total_supply.read(),
            'OVER_TOKEN_PURCHASED'
        );
        // assert(fractioned_unit_ <= token_owned, "OVER_TOKEN_PURCHASED");
        let caller = get_caller_address();
        // let orb_price = self.get_price();
        let address_this = get_contract_address();
        let usage_level_ = self.parameters_data.read(address_this).usage_level;
        let user_satisfaction_ = self.parameters_data.read(address_this).user_satisfaction;
        let subscription_demand_ = self.parameters_data.read(address_this).subscription_demand;

        let current_price_ = self
            .my_fractioned_orb_price(usage_level_, user_satisfaction_, subscription_demand_);
        let single_price = current_price_ / self.total_supply.read();

        let fractioned_price_ = single_price * fractioned_unit_;
        assert(amount_ >= fractioned_price_, 'NOT_CURRENT_PRICE');
        let balance_ = IERC20Dispatcher { contract_address: token_address_ }.balance_of(caller);
        assert(balance_ >= fractioned_price_, 'INSUFFICIENT_BALANCE');
        IERC20Dispatcher { contract_address: token_address_ }
            .transfer_from(caller, address_this, amount_);

        self.fractioned_balances.write(caller, fractioned_unit_);

        // let remaining_token_ =  fractioned_unit_ - self.token_owned.read();
        let token_purchased_ = self.token_owned.read() + fractioned_unit_;
        self.token_owned.write(token_purchased_);
        self.balances.write(self.owner.read(), amount_);
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        let extended_time = current_time + self.purchase_period.read();

        self.fractioned_token_id_owner.write(self.last_token_id.read() + 1, caller);
        self.fractioned_token_id.write(self.last_token_id.read() + 1, fractioned_unit_);
        self.subscription_time.write(self.last_token_id.read() + 1, extended_time);
        // increase subsrition demand
        let usage_level = self.parameters_data.read(get_contract_address()).usage_level + 0;
        let user_satisfaction = self.parameters_data.read(get_contract_address()).user_satisfaction
            + 0;
        let subscription_demand = self
            .parameters_data
            .read(get_contract_address())
            .user_satisfaction
            + 001;

        let parameters_data_ = Parameters { usage_level, user_satisfaction, subscription_demand };
        self.parameters_data.write(address_this, parameters_data_);
        self
            .emit(
                BuyOrb {
                    buyer_address: buyer_address,
                    amount_: fractioned_price_,
                    fractioned_unit_: fractioned_unit_,
                    token_id: self.last_token_id.read() + 1,
                }
            );
    }

    /// @notice buy premium when orb is not active
    /// @dev Emits 'NonActivePurchase'
    /// @param token_id_: Id of the fractioned token
    /// @param amount_ value to be paid for the fractioned Orb
    /// @param token_address_ Token address to be used as payment
    #[external(v0)]
    fn buy_nonactive_orb(
        ref self: ContractState, token_id_: u256, amount_: u256, token_address_: ContractAddress
    ) {
        let caller = get_caller_address();
        let current_time_: u256 = self.subscription_time.read(token_id_);
        let half_time_ = current_time_ / 2;
        assert(
            get_block_timestamp().try_into().unwrap() > half_time_,
            'IN_ACTIVENESS_NOTDETERMINED_YET'
        );
        assert(
            self.parameters_monitor.read(token_id_).usage_level > 0
                && self.parameters_monitor.read(token_id_).user_satisfaction > 0,
            'ACTIVE'
        );

        // let orb_price = self.get_price();
        let address_this = get_contract_address();
        let usage_level_ = self.parameters_data.read(address_this).usage_level;
        let user_satisfaction_ = self.parameters_data.read(address_this).user_satisfaction;
        let subscription_demand_ = self.parameters_data.read(address_this).subscription_demand;
        let current_price_ = self
            .my_fractioned_orb_price(usage_level_, user_satisfaction_, subscription_demand_);
        let single_price = current_price_ / self.total_supply.read();
        let unit_owed_by_id = self.fractioned_token_id.read(token_id_);
        let purchased_price_ = single_price * unit_owed_by_id;
        assert(amount_ >= purchased_price_, 'INPUT_THE_RIGHT_AMOUNT');
        let balance_ = IERC20Dispatcher { contract_address: token_address_ }.balance_of(caller);
        assert(balance_ >= purchased_price_, 'INSUFFICIENT_BALANCE');
        IERC20Dispatcher { contract_address: token_address_ }
            .transfer_from(caller, address_this, amount_);
        self.fractioned_token_id_owner.write(token_id_, caller);
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        let extended_time = current_time + self.purchase_period.read();
        let formal_owner = self.fractioned_token_id_owner.read(token_id_);
        let uint_owed = self.fractioned_balances.read(formal_owner);
        self.subscription_time.write(token_id_, extended_time);
        self.fractioned_balances.write(formal_owner, 0);
        self.fractioned_balances.write(caller, uint_owed);
        let usage_level = 0;
        let user_satisfaction = 0;
        let parameters_monitor_ = MonitorParameters { usage_level, user_satisfaction };
        self.parameters_monitor.write(token_id_, parameters_monitor_);
        self
            .emit(
                NonActivePurchase {
                    new_owner: caller,
                    previous_owner: formal_owner,
                    amount_: amount_,
                    token_id: token_id_
                }
            );
    }


    /// @notice deposit fund into the contract
    /// @dev Emits 'TokenDeposit'
    /// @param amount_ value to put into the contract
    /// @param token_address_ TOken address to be used as payment
    #[external(v0)]
    fn deposit(ref self: ContractState, amount_: u256, token_address_: ContractAddress) {
        let caller = get_caller_address();
        let address_this = get_contract_address();

        assert(self.fractioned_balances.read(caller) >= 1, 'NO_TOKEN_BALANCE');
        let balance_ = IERC20Dispatcher { contract_address: token_address_ }.balance_of(caller);
        assert(balance_ >= amount_, 'INSUFFICIENT_BALANCE');
        IERC20Dispatcher { contract_address: token_address_ }
            .transfer_from(caller, address_this, amount_);
        self.balances.write(caller, amount_);
        self.emit(TokenDeposit { owner: caller, amount: amount_ });
    }
    /// @notice withdrawAll your fund from the contract
    /// @dev Emits 'WithdrawFund'
    /// @param token_address_ TOken address to be used as payment
    #[external(v0)]
    fn withdraw_all_fund(ref self: ContractState, token_address_: ContractAddress) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        let my_balance = self.balances.read(caller);
        assert(my_balance > 0, 'NOT_ENOUGH_BALANCE');
        assert(
            IERC20Dispatcher { contract_address: token_address_ }
                .balance_of(address_this) >= my_balance,
            'TRY_AGAIN'
        );
        IERC20Dispatcher { contract_address: token_address_ }
            .transfer_from(address_this, caller, my_balance);
        self.balances.write(caller, self.balances.read(caller) - my_balance);
        self.emit(WithdrawFund { amount: my_balance, owner: caller });
    }
    /// @notice Withdraw fund from the contract
    /// @dev Emits 'WithdrawFund'
    /// @param token_address_ TOken address to be used as payment
    /// @param amount_ value of token to withdraw
    #[external(v0)]
    fn withdraw_fund(ref self: ContractState, amount_: u256, token_address_: ContractAddress) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        let my_balance = self.balances.read(caller);
        assert(my_balance > 0, 'NOT_ENOUGH_BALANCE');
        assert(amount_ <= my_balance, 'OVER_AMOUNT_INPUT');
        assert(
            IERC20Dispatcher { contract_address: token_address_ }
                .balance_of(address_this) >= my_balance,
            'TRY_AGAIN'
        );
        IERC20Dispatcher { contract_address: token_address_ }
            .transfer_from(address_this, caller, amount_);
        self.balances.write(caller, self.balances.read(caller) - amount_);
        self.emit(WithdrawFund { amount: my_balance, owner: caller });
    }

    /// @notice relinquish the orb: give up your Orb
    /// @dev Emits 'OrbReliquish'
    /// @param token_id_ id of the token to give up
    #[external(v0)]
    fn relinquish(ref self: ContractState, token_id_: u256,) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        // let set_time 
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        assert(self.fractioned_token_id_owner.read(token_id_) == caller, 'NOT_OWNER');
        assert(current_time < self.subscription_time.read(token_id_), 'ORB_NOT_ACTIVE');
        self.fractioned_token_id_owner.write(token_id_, address_this);
        self.subscription_time.write(token_id_, 0);
        let usage_level = 0;
        let user_satisfaction = 0;

        let parameters_ = MonitorParameters { usage_level, user_satisfaction };
        self.parameters_monitor.write(token_id_, parameters_);
        self.emit(OrbReliquish { orb_owner: caller, token_id: token_id_ });
    }
    /// @notice get the fractioned balance of the caller
    /// @param owner_ address of the fractioned balance owner
    /// @return balance of the owner
    #[external(v0)]
    fn my_fractioned_balance(self: @ContractState, owner_: ContractAddress) -> u256 {
        self.fractioned_balances.read(owner_)
    }

    /// @notice get ths subscription time left of the token_id_ in seconds
    /// @param token_id_ fractioned unit id of the 
    /// @return token_id time left in seconds 
    #[external(v0)]
    fn get_subscription_remaining_time(self: @ContractState, token_id_: u256) -> u256 {
        self.subscription_time.read(token_id_)
    }

    /// @notice  get last invocation time in seconds
    /// @param token_id_ fractioned unit id of the 
    /// @return token_id time of last invocation in seconds 
    #[external(v0)]
    fn my_last_invocation_time(self: @ContractState, token_id_: u256) -> u256 {
        self.last_invocation.read(token_id_)
    }
    /// @notice get invocation cooldown period
    #[external(v0)]
    fn get_invocation_period(self: @ContractState) -> u256 {
        self.cooldown.read()
    }

    /// @notice setLast invocation time
    /// @param token_id_ of the fractioned Orb
    /// @param_ owner_ fractioned Orb owner
    #[external(v0)]
    fn set_last_invocation_time(ref self: ContractState, token_id_: u256, owner_: ContractAddress) {
        assert(self.fractioned_balances.read(owner_) > 0, 'NO_TOKEN');
        assert(self.fractioned_token_id_owner.read(token_id_) == owner_, 'NOT_OWNER');
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        self.last_invocation.write(token_id_, current_time);
        self.emit(LastInvocation { token_id: token_id_, invocation_time: current_time });
    }

    /// @notice set premimum data by the user
    /// @param contract_address of the OrbPond
    /// @param usage_level_ value for how the Orb is used
    /// @param user_satisfaction_ value for how staisfied the caller is
    /// @param subscription_demand_ value for the demand of the Orb
    /// @param owner_ Fractioned Orb holder
    /// @param token_id_ id of the owners fractioned Orb
    #[external(v0)]
    fn set_premium_data_by_user(
        ref self: ContractState,
        contract_address: ContractAddress,
        usage_level_: u256,
        user_satisfaction_: u256,
        subscription_demand_: u256,
        owner_: ContractAddress,
        token_id_: u256
    ) {
        let address_this = get_contract_address();
        assert(
            OrbInvocationDispatcher { contract_address }
                .prevent_violation(address_this, owner_) == true,
            'NOT_ALLOWED'
        );
        let usage_level = usage_level_ + self.parameters_data.read(address_this).usage_level;
        let user_satisfaction = user_satisfaction_
            + self.parameters_data.read(address_this).user_satisfaction;
        let subscription_demand = subscription_demand_
            + self.parameters_data.read(address_this).subscription_demand;
        let parameters_ = Parameters { usage_level, user_satisfaction, subscription_demand };

        let usage_level1 = usage_level_ + self.parameters_monitor.read(token_id_).usage_level;
        let user_satisfaction1 = user_satisfaction_
            + self.parameters_monitor.read(token_id_).usage_level;
        let monitor_parameters = MonitorParameters {
            usage_level: usage_level1, user_satisfaction: user_satisfaction1
        };

        self.parameters_data.write(address_this, parameters_);
        self.parameters_monitor.write(token_id_, monitor_parameters);
    }

    /// @notice set premium data by owner
    /// @param contract_address of the OrbPond
    /// @param usage_level_ value for how the Orb is used
    /// @param user_satisfaction_ value for how staisfied the caller is
    /// @param subscription_demand_ value for the demand of the Orb
    /// @param owner_ Fractioned Orb Main Keeper

    #[external(v0)]
    fn set_premium_data_by_owner(
        ref self: ContractState,
        owner_: ContractAddress,
        contract_address: ContractAddress,
        usage_level_: u256,
        user_satisfaction_: u256,
        subscription_demand_: u256
    ) {
        let address_this = get_contract_address();
        assert(
            OrbInvocationDispatcher { contract_address }
                .prevent_violation_owner(address_this, owner_) == true,
            'NOT_OWNER'
        );
        let usage_level = usage_level_ + self.parameters_data.read(address_this).usage_level;
        let user_satisfaction = user_satisfaction_
            + self.parameters_data.read(address_this).user_satisfaction;
        let subscription_demand = subscription_demand_
            + self.parameters_data.read(address_this).subscription_demand;
        let parameters_ = Parameters { usage_level, user_satisfaction, subscription_demand };
        self.parameters_data.write(address_this, parameters_);
    }


    /// @notice foreclose can be called by anyone on a particular fractioned token_id if the holder refused to renew its subscription 
    /// @dev Emits 'ForeClosure'
    /// @param token-id_ Fractioned Orb id 
    #[external(v0)]
    fn foreclose(ref self: ContractState, token_id_: u256) {
        let address_this = get_contract_address();
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        assert(current_time > self.subscription_time.read(token_id_), 'ORB_ISACTIVE');
        self.fractioned_token_id_owner.write(token_id_, address_this);
        self.subscription_time.write(token_id_, 0);
        let usage_level = 0;
        let user_satisfaction = 0;

        let parameters_ = MonitorParameters { usage_level, user_satisfaction };
        self.parameters_monitor.write(token_id_, parameters_);
        self.emit(ForeClosure { token_id: token_id_ })
    }
    /// @notice check address if owner
    /// @param owner_ address to check status on
    /// @returns the status oof the address 
    #[external(v0)]
    fn get_owner(self: @ContractState, owner_: ContractAddress) -> bool {
        self.only_owner(owner_)
    }

    /// @notice get flagging period for Invocation 
    #[external(v0)]
    fn get_flagging_period(self: @ContractState) -> u256 {
        self.flagging_period.read()
    }

    /// @notice get Pond address
    #[external(v0)]
    fn get_pond_address(self: @ContractState) -> ContractAddress {
        self.pond.read()
    }
    /// @notice return main owner Address 
    #[external(v0)]
    fn main_keeper(self: @ContractState) -> ContractAddress {
        self.owner.read()
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        /// @notice return owner 
        fn only_owner(self: @ContractState, owner_: ContractAddress) -> bool {
            if (owner_ != self.owner.read()) {
                false
            } else {
                true
            }
        }

        /// @notice set the total orb Price
        /// @param price_ value of which the Orb is been willing to be given up for
        fn set_price_(ref self: ContractState, price_: u256) {
            assert(self.price.read() == 0, 'PRICE_AVAILABLE');
            self.price.write(price_);
        }

        // @notice get the set price
        fn get_price(self: @ContractState) -> u256 {
            self.price.read()
        }

        // @notice Orb single Price
        fn my_fractioned_orb_price(
            self: @ContractState,
            usage_level_: u256,
            user_satisfaction_: u256,
            subscription_demand_: u256
        ) -> u256 {
            let orb_price = self.get_price();
            let premium_price = self
                .calculate_premium(
                    orb_price, usage_level_, subscription_demand_, user_satisfaction_
                );
            let fractioned_price = premium_price / self.total_supply.read();
            fractioned_price
        }
        // @notice determine premium price
        fn calculate_premium(
            self: @ContractState,
            price_: u256,
            usage_level_: u256,
            subscription_demand_: u256,
            user_satisfaction_: u256
        ) -> u256 {
            // let my_satisfaction:u256 = user_satisfaction_.into().unwrap();
            if (usage_level_ == 0 && subscription_demand_ == 0 && user_satisfaction_ == 0) {
                self.price.read()
            } else {
                let newPrice = (price_
                    * (10
                        + ((WEIGHT_USAGE_LEVEL * usage_level_) / 10)
                        + ((WEIGHT_SUBSCRIPTION_DEMAND * subscription_demand_) / 10)
                        + ((WEIGHT_USER_SATISFACTION * user_satisfaction_) / 10)))
                    / 10;
                newPrice
            }
        }
    }
}
