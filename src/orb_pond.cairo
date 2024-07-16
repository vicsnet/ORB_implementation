#[starknet::contract]
mod ORB_pond {
    use starknet::{
        ContractAddress, ClassHash, SyscallResultTrait, syscalls::deploy_syscall, get_caller_address
    };

    // Orb pond version
    const VERSION: u256 = 1;
    #[storage]
    struct Storage {
        ORBHash: ClassHash,
        // deployer_ address
        owner: ContractAddress,
        // the mapping of Orb ids to Orbs.
        orbs: LegacyMap::<u256, ContractAddress>,
        orb_count: u256,
        registry: ContractAddress,
        latest_version: u256,
        orb_initial_version: u256,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    // @notice create a new orb
    // payees
    // shares
    #[external(v0)]
    fn create_orb(
        ref self: ContractState,
        name_: felt252,
        symbol_: felt252,
        token_uri_: felt252,
        total_supply_: u256,
    ) -> ContractAddress {
        let mut constructor_calldata = ArrayTrait::new();
        name_.serialize(ref constructor_calldata);
        symbol_.serialize(ref constructor_calldata);
        total_supply_.serialize(ref constructor_calldata);
        token_uri_.serialize(ref constructor_calldata);
        get_caller_address().serialize(ref constructor_calldata);

        let (deployed_address, _) = deploy_syscall(
            self.ORBHash.read(), 0, constructor_calldata.span(), false
        )
            .expect('FAILED_TO_DEPLOY');

        self.orbs.write(self.orb_count.read(), deployed_address);
        self.orb_count.write(self.orb_count.read() + 1);

        deployed_address
    }
    // register orb version
    fn register_version(ref self: ContractState, version_: u256, orb_class_hash_: ClassHash) {
        assert(self.owner.read() == get_caller_address(), 'NOT_OWNER');
        assert(version_ > self.latest_version.read(), 'INVALID_VERSION');
        self.latest_version.write(version_);
        self.ORBHash.write(orb_class_hash_)
    }

    // version
    #[external(v0)]
    fn version(self: @ContractState) -> u256 {
        VERSION
    }

    // set orb initial version
    #[external(v0)]
    fn set_orb_initial_version(ref self: ContractState, orb_initial_version_: u256) {
        assert(self.owner.read() == get_caller_address(), 'NOT_OWNER');
        assert(orb_initial_version_ < self.latest_version.read(), 'INVALID_VERSION');
        let previous_version_ = self.orb_initial_version.read();
        self.orb_initial_version.write(previous_version_);
    }

    #[external(v0)]
    fn get_registry(self: @ContractState) -> ContractAddress {
        self.registry.read()
    }

    #[external(v0)]
    fn set_registry(ref self: ContractState,) {}
}
