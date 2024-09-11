use starknet::{ContractAddress, ClassHash};
#[starknet::interface]
pub trait IOrbPondTrait<TContractState> {
    fn create_orb(
        ref self: TContractState,
        name_: felt252,
        symbol_: felt252,
        token_uri_: ByteArray,
        total_supply_: u256,
    ) -> ContractAddress;

    fn register_version(ref self: TContractState, version_: u256, orb_class_hash_: ClassHash);

    fn version(self: @TContractState) -> u256;
    fn set_orb_initial_version(ref self: TContractState, orb_initial_version_: u256);
    fn get_registry(self: @TContractState) -> ContractAddress;
    fn get_owner(self: @TContractState) -> ContractAddress;
    
}


#[starknet::contract]
pub mod ORB_pond {
    use core::num::traits::Zero;
    use core::starknet::event::EventEmitter;
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
        /// The number of Orb  created so far
        orb_count: u256,
        /// The address of the Orb Invocation Registry, used to register Orb invocations and responses
        registry: ContractAddress,
        /// The highest version number so far. Could be used for new Orb Creation
        latest_version: u256,
        /// New Orb version
        orb_initial_version: u256,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OrbCreated: OrbCreated,
        VersionRegistration: VersionRegistration,
        OrbInitialVersionUpdate: OrbInitialVersionUpdate
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrbCreated {
        #[key]
        pub contract_address: ContractAddress
    }
    #[derive(Drop, starknet::Event)]
    pub struct VersionRegistration {
        #[key]
        pub version: u256,
        pub class_hash: ClassHash
    }
    #[derive(Drop, starknet::Event)]
    pub struct OrbInitialVersionUpdate {
        #[key]
        pub previous_version: u256,
        pub orb_initial_version: u256
    }
    /// @notice Contract Initalizes, setting owner and registry 
    /// @param registry_ The adddress of the Orb Invocation Registry
    #[constructor]
    fn constructor(ref self: ContractState, registry_: ContractAddress, owner_:ContractAddress) {
        // let owner_address = get_caller_address();  
        // assert(owner_ == owner_address, 'ADDRESS_DOES_NOT_MATCH');
        self.owner.write( owner_);
        self.registry.write(registry_)
    }
    
    #[abi(embed_v0)]
    impl OrbPond of super::IOrbPondTrait<ContractState> {
        /// @notice create a new Orb
        /// @dev Emits 'OrbCreated' 
        /// @param name_ Name of the Orb used for display Purposs
        /// @param symbol_ Symbol of the Orb, used for display Purpose
        /// @param token_uri_ Initial token_uri_ of the Orb, used as part of ERC721
        /// @param total_supply_ Fractionalized total of the OrbCreated   
        fn create_orb(
            ref self: ContractState,
            name_: felt252,
            symbol_: felt252,
            token_uri_: ByteArray,
            total_supply_: u256,
        ) -> ContractAddress {
            assert(!self.ORBHash.read().is_zero(), 'SET_ORBHASH');
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
            self.emit(OrbCreated { contract_address: deployed_address });

            deployed_address
        }

       
        /// @notice Register a new version of the Orb Implementation Contract
        /// @dev Emits 'VersionRegistration'
        /// @param  version_ Version number of the new implementation contract
        /// @param orb_class_hash_ Implementation of the new Orb
        fn register_version(ref self: ContractState, version_: u256, orb_class_hash_: ClassHash) {
            assert(self.owner.read() == get_caller_address(), 'NOT_OWNER');
            assert(version_ > self.latest_version.read(), 'INVALID_VERSION');
            self.latest_version.write(version_);
            self.ORBHash.write(orb_class_hash_);
            self.emit(VersionRegistration { version: version_, class_hash: orb_class_hash_ });
        }

        /// @notice Returns the version of the Orb Pond.
        fn version(self: @ContractState) -> u256 {
            VERSION
        }

        /// @notice Sets the registered Orb Implementation version and class hash to be used for the Orb
        /// @dev Emits 'OrbInitialVersionUpdate'
        /// @param orb_initial_version_ Registered Orb implementation version number to be used for new Orbs
        fn set_orb_initial_version(ref self: ContractState, orb_initial_version_: u256) {
            assert(self.owner.read() == get_caller_address(), 'NOT_OWNER');
            assert(orb_initial_version_ < self.latest_version.read(), 'INVALID_VERSION');
            let previous_version_ = self.orb_initial_version.read();
            self.orb_initial_version.write(previous_version_);
            self
                .emit(
                    OrbInitialVersionUpdate {
                        previous_version: previous_version_,
                        orb_initial_version: orb_initial_version_
                    }
                );
        }

        /// @notice  Returns registry address
        fn get_registry(self: @ContractState) -> ContractAddress {
            self.registry.read()
        }

        /// @notice Returns Contract owner address
        fn get_owner(self: @ContractState) -> ContractAddress{
            self.owner.read()
        }

    }

  
}
