use starknet::{ContractAddress};
#[starknet::interface]
trait IORB<TContractState> {
    fn my_fractioned_balance(self: @TContractState, owner_: ContractAddress) -> u256;
    fn get_subscription_remaining_time(self: @TContractState, token_id_: u256) -> u256;
    fn set_last_invocation_time(ref self: TContractState, token_id_: u256, owner_: ContractAddress);
    fn get_invocation_period(self: @TContractState) -> u256;
    fn my_last_invocation_time(self: @TContractState, token_id_: u256) -> u256;
    fn get_owner(self: @TContractState, owner_: ContractAddress) -> bool;
}

#[starknet::contract]
mod ORB_Invocation_Registry {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
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
        //  Addresses authorised o for external calls in invokeWithXAndCall 
        // dont know why yet

        authorized_contract: LegacyMap::<ContractAddress, bool>,
        // Gap used to prevent storage collisions

        gap: u256,
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct InvocationData {
        content_hash: ByteArray,
        time_stamp: u256
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct ResponseData {
        content_hash: ByteArray,
        time_stamp: u256,
    }


    // @notice Invokes the orb
    #[external(v0)]
    // fn invoke_with_clear_text(ref self:ContractState){

    // }

    // invokes the orb with clear text and calls an external contract
    #[external(v0)]
    // fn invokeWithCleartextandCall(ref self: ContractState) {

    // }

    // @notice invokes the Orb. Allow the keeper to submit content hash
    #[external(v0)]
    fn invoke_with_hash(
        ref self: ContractState,
        content_hash_: ByteArray,
        contract_address: ContractAddress,
        token_id_: u256
    ) {
        let caller = get_caller_address();
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
        let time_stamp = current_time;
        let invocation_data_ = InvocationData { content_hash, time_stamp };
        self.invocations.write((contract_address, id), invocation_data_);
        IORBDispatcher { contract_address }.set_last_invocation_time(token_id_, caller);
    // emit event

    }
    // @notice invokes the orb with content has and calls an external contract
    #[external(v0)]
    fn invoke_with_hash_and_call(ref self: ContractState) {}

    // Responding
    #[external(v0)]
    fn respond(
        ref self: ContractState,
        invocation_id: u256,
        content_hash: ByteArray,
        contract_address: ContractAddress
    ) {
        let caller = get_caller_address();
    }

    // flag response
    #[external(v0)]
    fn flag_response(ref self: ContractState) {}
}
