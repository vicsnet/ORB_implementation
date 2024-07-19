use starknet::{ContractAddress};
#[starknet::interface]
trait IORB<TContractState> {
    fn my_fractioned_balance(self: @TContractState, owner_: ContractAddress) -> u256;
    fn get_subscription_remaining_time(self: @TContractState, token_id_: u256) -> u256;
    fn set_last_invocation_time(ref self: TContractState, token_id_: u256, owner_: ContractAddress);
    fn get_invocation_period(self: @TContractState) -> u256;
    fn my_last_invocation_time(self: @TContractState, token_id_: u256) -> u256;
    fn get_owner(self: @TContractState, owner_: ContractAddress) -> bool;
    fn set_premium_data_by_user(
        ref self: TContractState,
        contract_address: ContractAddress,
        usage_level_: u256,
        user_satisfaction_: u256,
        subscription_demand_: u256,
        owner_: ContractAddress,
        token_id_: u256
    );
    fn set_premium_data_by_owner(
        ref self: TContractState,
        owner_: ContractAddress,
        contract_address: ContractAddress,
        usage_level_: u256,
        user_satisfaction_: u256,
        subscription_demand_: u256
    );
    fn get_flagging_period(self: @TContractState) -> u256;
}

#[starknet::contract]
mod ORB_Invocation_Registry {
    use core::starknet::event::EventEmitter;
    use core::clone::Clone;
    use core::traits::Into;
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use super::{IORBDispatcher, IORBDispatcherTrait};
    #[storage]
    struct Storage {
        // this tracks the address of the orb, invocation id, to the invocation struct

        invocations: LegacyMap::<(ContractAddress, u256), InvocationData>,
        // Count of Invocation made
        // it includes the address of the Orb and the invocation ID 
        invocation_count: LegacyMap::<ContractAddress, u256>,
        // Mapping for responses (answer to invocations): matching invocationId toresponsedata struct

        responses: LegacyMap::<(ContractAddress, u256), ResponseData>,
        // Mapping of flagged (reported) responses by the holder

        response_flagged: LegacyMap::<(ContractAddress, u256), bool>,
        // response_rating 
        response_rating: LegacyMap::<(ContractAddress, u256), bool>,
        //  Addresses authorised o for external calls in invokeWithXAndCall 
        // dont know why yet

        authorized_contract: LegacyMap::<ContractAddress, bool>,
        // Gap used to prevent storage collisions
        gap: u256,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct InvocationData {
        invoker: ContractAddress,
        content_hash: ByteArray,
        time_stamp: u256
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct ResponseData {
        content_hash: ByteArray,
        time_stamp: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Invocation: Invocation,
        Response: Response,
        ResponseFlagging: ResponseFlagging,
        PositiveRating: PositiveRating
    }
    #[derive(Drop, starknet::Event)]
    struct Invocation {
        #[key]
        orb_address: ContractAddress,
        invocation_id: u256,
        invoker: ContractAddress,
        time_stamp: u256,
        content_hash: ByteArray
    }
    #[derive(Drop, starknet::Event)]
    struct Response {
        #[key]
        orb_address: ContractAddress,
        invocation_id: u256,
        responder: ContractAddress,
        time_stamp: u256,
        content_hash: ByteArray
    }
    #[derive(Drop, starknet::Event)]
    struct ResponseFlagging {
        #[key]
        orb_address: ContractAddress,
        invocation_id: u256,
        flager: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    struct PositiveRating {
        #[key]
        orb_address: ContractAddress,
        invocation_id: u256,
        usage_level: u256,
        user_satisfaction: u256,
    }
    /// @notice this function prevent the nft contract from been violated
    /// @param contract_address Address of the Orb
    /// @param owner_ Address of the Fractioned token Owner
    #[external(v0)]
    fn prevent_violation(
        self: @ContractState, contract_address: ContractAddress, owner_: ContractAddress
    ) -> bool {
        assert(
            IORBDispatcher { contract_address }.my_fractioned_balance(owner_) > 0, 'NOT_ALLOWED'
        );
        true
    }

    /// @notice prevent violation by the main Orb_keeper
    /// @param contract_address Address of the Orb
    /// @param owner_ Address of the main keeper
    #[external(v0)]
    fn prevent_violation_owner(
        self: @ContractState, contract_address: ContractAddress, owner_: ContractAddress
    ) -> bool {
        assert(IORBDispatcher { contract_address }.get_owner(owner_) == true, 'NOT_OWNER');
        true
    }

    /// @notice invokes the Orb. Allow the Fractioned Orb holder to submit content hash
    /// @dev Emits 'Invocation'
    /// @param content_hash_ hash of the cleartext
    /// @param contract_address Address of the Orb
    /// @param token_id_ Id of the token owned

    #[external(v0)]
    fn invoke_with_hash(
        ref self: ContractState,
        content_hash_: ByteArray,
        contract_address: ContractAddress,
        token_id_: u256
    ) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        // check if caller has a token id
        assert(
            IORBDispatcher { contract_address }.my_fractioned_balance(caller) > 0,
            'INVOCATION_NOT_ALLOWED'
        );
        assert(
            current_time > IORBDispatcher { contract_address }.my_last_invocation_time(token_id_)
                + IORBDispatcher { contract_address }.get_invocation_period(),
            'COOL_DOWN_IN_PROGRESS'
        );
        let id = self.invocation_count.read(contract_address) + 1;
        self.invocation_count.write(contract_address, id);

        let content_hash = content_hash_;

        let content_hash_data = content_hash.clone();
        let time_stamp = current_time;
        let invocation_data_ = InvocationData { invoker: caller, content_hash, time_stamp };
        self.invocations.write((contract_address, id), invocation_data_);
        IORBDispatcher { contract_address }.set_last_invocation_time(token_id_, caller);
        let usage_level_ = 001;
        IORBDispatcher { contract_address }
            .set_premium_data_by_user(address_this, usage_level_, 0, 0, caller, token_id_);
        self
            .emit(
                Invocation {
                    orb_address: contract_address,
                    invocation_id: id,
                    invoker: caller,
                    time_stamp: current_time,
                    content_hash: content_hash_data
                }
            )
    }


    /// @notice The Orb creator can use this function to respond to any existing invocation
    /// @dev Emits 'Response'
    /// @param invocation_id Id of an invocation can only be written once.
    /// @param content_hash_ hash of the response text
    /// @param contract_address Address of the Orb
    #[external(v0)]
    fn respond(
        ref self: ContractState,
        invocation_id: u256,
        content_hash_: ByteArray,
        contract_address: ContractAddress
    ) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        let usage_level_ = 001;
        assert(IORBDispatcher { contract_address }.get_owner(caller) == true, 'NOT_OWNER');
        assert(self.response_exists(contract_address, invocation_id), 'RESPONSE_EXIST');
        let content_hash = content_hash_;
        let content_hash_data = content_hash.clone();
        let time_stamp: u256 = get_block_timestamp().try_into().unwrap();

        let data = ResponseData { content_hash, time_stamp };
        self.responses.write((contract_address, invocation_id), data);
        IORBDispatcher { contract_address }
            .set_premium_data_by_owner(caller, address_this, usage_level_, 0, 0);
        self
            .emit(
                Response {
                    orb_address: contract_address,
                    invocation_id: invocation_id,
                    responder: caller,
                    time_stamp: time_stamp,
                    content_hash: content_hash_data
                }
            )
    }

    /// @notice Fractioned Orb holder can flag Response durring Flagging period
    /// @dev Emits 'ResponseFlagging'
    /// @param contract_address Address of the Orb
    /// @param invocation_id_ Id of an invocation to which the response is being flagged
    #[external(v0)]
    fn flag_response(
        ref self: ContractState,
        contract_address: ContractAddress,
        invocation_id_: u256,
        token_id_: u256
    ) {
        let address_this = get_contract_address();
        let caller = get_caller_address();

        assert(self.response_exists(contract_address, invocation_id_) == false, 'RESPONSE_EXIST');
        let flagging_time = IORBDispatcher { contract_address }.get_flagging_period();
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        let response_time = self.responses.read((contract_address, invocation_id_)).time_stamp;
        assert(response_time + flagging_time > current_time, 'TIME_ELAPSE');

        assert(
            self.response_flagged.read((contract_address, invocation_id_)) == false,
            'ALREADY_FLAGGED'
        );
        assert(
            self.response_rating.read((contract_address, invocation_id_)) == false, 'POSITIVE_RATED'
        );

        self.response_flagged.write((contract_address, invocation_id_), true);
        let usage_level_ = 001;
        let user_satisfaction_: i64 = -001;

        let sat: u128 = user_satisfaction_.try_into().unwrap();

        let user_sat: u256 = sat.into();
        IORBDispatcher { contract_address }
            .set_premium_data_by_user(address_this, usage_level_, user_sat, 0, caller, token_id_);
        self
            .emit(
                ResponseFlagging {
                    orb_address: contract_address, invocation_id: invocation_id_, flager: caller
                }
            )
    }

    /// @notice Rate invocation response positively
    /// @dev Emits 'PositiveRating'
    /// @param contract_address Address of the Orb
    /// @param invocation_id_ Id of the invocated content
    /// @param token_id_ Fractioned token Id of the Orb
    fn rate_Positive_reponse(
        ref self: ContractState,
        contract_address: ContractAddress,
        invocation_id_: u256,
        token_id_: u256
    ) {
        let caller = get_caller_address();
        let address_this = get_contract_address();
        assert(self.response_exists(contract_address, invocation_id_) == false, 'RESPONSE_EXIST');
        let flagging_time = IORBDispatcher { contract_address }.get_flagging_period();
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        let response_time = self.responses.read((contract_address, invocation_id_)).time_stamp;
        assert(response_time + flagging_time > current_time, 'TIME_ELAPSE');

        assert(
            self.response_flagged.read((contract_address, invocation_id_)) == false,
            'ALREADY_FLAGGED'
        );
        assert(
            self.response_rating.read((contract_address, invocation_id_)) == false, 'POSITIVE_RATED'
        );
        self.response_rating.write((contract_address, invocation_id_), true);
        let usage_level_ = 001;
        let user_satisfaction_ = 001;
        IORBDispatcher { contract_address }
            .set_premium_data_by_user(
                address_this, usage_level_, user_satisfaction_, 0, caller, token_id_
            );
        self
            .emit(
                PositiveRating {
                    orb_address: contract_address,
                    invocation_id: invocation_id_,
                    usage_level: usage_level_,
                    user_satisfaction: user_satisfaction_,
                }
            );
    }

    /// @notice get the details of the invocation
    /// @param orb_address Address of the Orb
    /// @param invocation_id_ Id of an invocation to which to check the existence of a response of
    /// @return content_data, address of invoker

    #[external(v0)]
    fn get_invocations(
        self: @ContractState, orb_address: ContractAddress, invocation_id_: u256
    ) -> (ByteArray, ContractAddress) {
        let invocation_data = self.invocations.read((orb_address, invocation_id_));
        (invocation_data.content_hash, invocation_data.invoker)
    }


    #[generate_trait]
    impl Private of PrivateTrait {
        fn response_exists(
            self: @ContractState, contract_address: ContractAddress, invocation_id: u256
        ) -> bool {
            if (self.responses.read((contract_address, invocation_id)).time_stamp != 0) {
                true
            } else {
                false
            }
        }
    }
}
