use core::option::OptionTrait;
use core::traits::TryInto;
use core::serde::Serde;
use starknet::{ContractAddress, ClassHash};

use snforge_std::{
    declare, ContractClassTrait, cheat_caller_address, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpy, SpyOn, EventAssertions, EventFetcher,
    start_cheat_block_timestamp, stop_cheat_block_timestamp
};

use orbland::orb::{IOrbTraitDispatcher, IOrbTraitDispatcherTrait};
use orbland::orb_pond::{IOrbPondTraitDispatcher, IOrbPondTraitDispatcherTrait, ORB_pond};

use orbland::orb_invocation_registry::{
    IOrbInvocationRegistryTraitDispatcher, IOrbInvocationRegistryTraitDispatcherTrait,
    ORBInvocationRegistry
};

use orbland::orb_invocation_tip_jar::{
    OrbInvocationTipJarTraitDispatcher, OrbInvocationTipJarTraitDispatcherTrait, ORB_invocation_tipJar
};

use orbland::mock_erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

fn deploy_orb(
    name_: felt252,
    symbol_: felt252,
    total_supply_: u256,
    token_uri_: ByteArray,
    owner_: ContractAddress
) -> ContractAddress {
    let contract = declare("ORB").unwrap();
    let mut calldata = ArrayTrait::new();
    name_.serialize(ref calldata);
    symbol_.serialize(ref calldata);
    total_supply_.serialize(ref calldata);
    token_uri_.serialize(ref calldata);
    owner_.serialize(ref calldata);
    // Precalculate the address to obtain the contract address before the constructor call (deploy) itself
    let contract_address = contract.precalculate_address(@calldata);
    start_cheat_caller_address(contract_address, owner_.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();
    stop_cheat_caller_address(contract_address);

    deployedContract
}

fn deploy_erc20(_name: felt252, _symbol: felt252, _decimal: u8,) -> ContractAddress {
    let contract = declare("erc20").unwrap();
    let mut calldata = ArrayTrait::new();
    _name.serialize(ref calldata);
    _symbol.serialize(ref calldata);
    _decimal.serialize(ref calldata);

    let contract_address = contract.precalculate_address(@calldata);
    start_cheat_caller_address(contract_address, 123.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();
    stop_cheat_caller_address(contract_address);

    deployedContract
}

fn deploy_orbpond_contract(registry_: ContractAddress) -> ContractAddress {
    let contract = declare("ORB_pond").unwrap();
    let mut calldata = ArrayTrait::new();
    registry_.serialize(ref calldata);

    // precalculate address

    let contract_address = contract.precalculate_address(@calldata);
    start_cheat_caller_address(contract_address, 123.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();
    stop_cheat_caller_address(contract_address);
    deployedContract
}

fn deploy_orbinvocation_registry(owner: ContractAddress) -> ContractAddress {
    let contract = declare("ORBInvocationRegistry").unwrap();
    let mut calldata = ArrayTrait::new();

    owner.serialize(ref calldata);

    // Precalculate the address to obtain the contract address before the constructor call (deploy) itself
    let contract_address = contract.precalculate_address(@calldata);
    start_cheat_caller_address(contract_address, owner.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();

    stop_cheat_caller_address(contract_address);

    deployedContract
}

fn deploy_orb_invocation_tipjar(owner:ContractAddress) -> ContractAddress {
    let contract = declare("ORB_invocation_tipJar").unwrap();
    let mut calldata = ArrayTrait::new();

    owner.serialize(ref calldata);
    //  precalculate address 
    let contract_address = contract.precalculate_address(@calldata);

    start_cheat_caller_address(contract_address, owner.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();

    stop_cheat_caller_address(contract_address);

    deployedContract
}

#[test]
fn test_orb_version() {
    let owner: ContractAddress = 123.try_into().unwrap();
    let registry_address = deploy_orbinvocation_registry(owner);
    let orb_pond_address = deploy_orbpond_contract(registry_address);
    let owner: ContractAddress = 123.try_into().unwrap();
    let mut spy = spy_events(SpyOn::One(orb_pond_address));
    let orbpond_dispatcher = IOrbPondTraitDispatcher { contract_address: orb_pond_address };
    let orb_class = declare("ORB").unwrap();
    let hash: ClassHash = orb_class.class_hash;

    start_cheat_caller_address(orb_pond_address, owner);
    orbpond_dispatcher.register_version(1, hash);
    spy
        .assert_emitted(
            @array![
                (
                    orb_pond_address,
                    ORB_pond::Event::VersionRegistration(
                        ORB_pond::VersionRegistration { version: 1, class_hash: hash }
                    )
                )
            ]
        );

    orbpond_dispatcher.set_orb_initial_version(0);
    spy
        .assert_emitted(
            @array![
                (
                    orb_pond_address,
                    ORB_pond::Event::OrbInitialVersionUpdate(
                        ORB_pond::OrbInitialVersionUpdate {
                            previous_version: 0, orb_initial_version: 0
                        }
                    )
                )
            ]
        );
    stop_cheat_caller_address(orb_pond_address);
}

fn create_orb() -> ContractAddress {
    let newKeeper: ContractAddress = 124.try_into().unwrap();
    let owner: ContractAddress = 123.try_into().unwrap();
    let orb_class = declare("ORB").unwrap();
    let hash: ClassHash = orb_class.class_hash;

    let registry_address = deploy_orbinvocation_registry(owner);

    let orb_pond_address = deploy_orbpond_contract(registry_address);

    let mut spy = spy_events(SpyOn::One(orb_pond_address));

    let orbpond_dispatcher = IOrbPondTraitDispatcher { contract_address: orb_pond_address };

    start_cheat_caller_address(orb_pond_address, owner);
    orbpond_dispatcher.register_version(1, hash);

    stop_cheat_caller_address(orb_pond_address);

    start_cheat_caller_address(orb_pond_address, newKeeper);
    let uri:ByteArray ="qwertyue";

    let new_orb_address = orbpond_dispatcher.create_orb('vinceOrb', 'VOB', uri, 5);
    stop_cheat_caller_address(orb_pond_address);
    spy
        .assert_emitted(
            @array![
                (
                    orb_pond_address,
                    ORB_pond::Event::OrbCreated(
                        ORB_pond::OrbCreated { contract_address: new_orb_address }
                    )
                )
            ]
        );

    new_orb_address
}
#[test]
fn test_create_orb() {
    create_orb();
}


fn start_orb() -> ContractAddress {
    let newKeeper: ContractAddress = 124.try_into().unwrap();
    let orb_contractAddress = create_orb();

    let orbDispatcher = IOrbTraitDispatcher { contract_address: orb_contractAddress };
    start_cheat_caller_address(orb_contractAddress, newKeeper);
    orbDispatcher.set_price(1000);

    orbDispatcher.swear_oath("hellop", 14400, 1440);

    orbDispatcher.start_orb();
    stop_cheat_caller_address(orb_contractAddress);
    orb_contractAddress
}


fn mint_token() -> (
    ContractAddress,
    ContractAddress,
    ContractAddress,
    ContractAddress,
    ContractAddress,
    ContractAddress,
    ContractAddress
) {
    let buyer1: ContractAddress = 01456.try_into().unwrap();

    let buyer2: ContractAddress = 05678.try_into().unwrap();

    let buyer3: ContractAddress = 0789.try_into().unwrap();

    let buyer4: ContractAddress = 89765.try_into().unwrap();

    let buyer5: ContractAddress = 98134.try_into().unwrap();

    let orbContractAddress = start_orb();

    let tokenAddress = deploy_erc20('OrbToken', 'OTK', 18);

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    start_cheat_caller_address(tokenAddress, buyer1);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(orbContractAddress, 500);
    stop_cheat_caller_address(tokenAddress);

    start_cheat_caller_address(tokenAddress, buyer2);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(orbContractAddress, 500);
    stop_cheat_caller_address(tokenAddress);

    start_cheat_caller_address(tokenAddress, buyer3);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(orbContractAddress, 500);
    stop_cheat_caller_address(tokenAddress);

    start_cheat_caller_address(tokenAddress, buyer4);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(orbContractAddress, 500);
    stop_cheat_caller_address(tokenAddress);

    start_cheat_caller_address(tokenAddress, buyer5);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(orbContractAddress, 500);
    stop_cheat_caller_address(tokenAddress);

    (buyer1, buyer2, buyer3, buyer4, buyer5, orbContractAddress, tokenAddress)
}

#[test]
fn test_buy_orb() {
    let (buyer1, buyer2, _, _, _, orbContractAddress, tokenAddress) = mint_token();
    let orbDispatcher = IOrbTraitDispatcher { contract_address: orbContractAddress };

    start_cheat_caller_address(orbContractAddress, buyer1);
    orbDispatcher.buy_orb(buyer1, 200, tokenAddress, 1);
    stop_cheat_caller_address(orbContractAddress);

    start_cheat_caller_address(orbContractAddress, buyer2);
    orbDispatcher.buy_orb(buyer2, 400, tokenAddress, 2);
    stop_cheat_caller_address(orbContractAddress);
}


fn invokeHash() -> (ContractAddress, ContractAddress) {
    let owner: ContractAddress = 123.try_into().unwrap();
    let newKeeper: ContractAddress = 124.try_into().unwrap();
    let buyer1: ContractAddress = 01456.try_into().unwrap();

    let orbInvocationAddress = deploy_orbinvocation_registry(owner);

    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };

    let orb_class = declare("ORB").unwrap();
    let hash: ClassHash = orb_class.class_hash;

    let orb_pond_address = deploy_orbpond_contract(orbInvocationAddress);

    let orbpond_dispatcher = IOrbPondTraitDispatcher { contract_address: orb_pond_address };
    start_cheat_caller_address(orb_pond_address, owner);
    orbpond_dispatcher.register_version(1, hash);
    stop_cheat_caller_address(orb_pond_address);

    start_cheat_caller_address(orb_pond_address, newKeeper);
    let uri:ByteArray ="qwertyue";
    let new_orb_address = orbpond_dispatcher.create_orb('vinceOrb', 'VOB', uri, 5);

    stop_cheat_caller_address(orb_pond_address);

    let tokenAddress = deploy_erc20('OrbToken', 'OTK', 18);

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };

    start_cheat_caller_address(tokenAddress, buyer1);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(new_orb_address, 500);
    stop_cheat_caller_address(tokenAddress);

    let orbDispatcher = IOrbTraitDispatcher { contract_address: new_orb_address };

    start_cheat_caller_address(new_orb_address, newKeeper);
    orbDispatcher.set_price(1000);

    orbDispatcher.swear_oath("hellop", 14400, 1440);

    orbDispatcher.start_orb();
    stop_cheat_caller_address(new_orb_address);

    start_cheat_caller_address(new_orb_address, buyer1);

    orbDispatcher.buy_orb(buyer1, 200, tokenAddress, 1);
    stop_cheat_caller_address(new_orb_address);

    let mut spy = spy_events(SpyOn::One(orbInvocationAddress));

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    start_cheat_block_timestamp(orbInvocationAddress, 20);
    orbInvocationDispatcher.invoke_with_hash("qwerty", new_orb_address, 1);

    spy
    .assert_emitted(
        @array![
            (
                orbInvocationAddress,
                ORBInvocationRegistry::Event::Invocation(
                    ORBInvocationRegistry::Invocation {
                        orb_address: new_orb_address,
                        invocation_id: 1,
                        invoker: buyer1,
                        time_stamp: 20,
                        content_hash: "qwerty"
                    }
                )
            )
        ]
    );
    stop_cheat_block_timestamp(orbInvocationAddress);
    stop_cheat_caller_address(orbInvocationAddress);

    // RESPOND 
    start_cheat_caller_address(orbInvocationAddress, newKeeper);
    start_cheat_block_timestamp(orbInvocationAddress, 40);
    orbInvocationDispatcher.respond(1, "qwertqwey", new_orb_address);

    spy
    .assert_emitted(
        @array![
            (
                orbInvocationAddress,
                ORBInvocationRegistry::Event::Response(
                    ORBInvocationRegistry::Response {
                        orb_address: new_orb_address,
                        invocation_id: 1,
                        responder: newKeeper,
                        time_stamp: 40,
                        content_hash: "qwertqwey"
                    }
                )
            )
        ]
    );
    stop_cheat_block_timestamp(orbInvocationAddress);
    stop_cheat_caller_address(orbInvocationAddress);

    (new_orb_address, orbInvocationAddress)
}

#[test]
fn test_flag_response() {
    let buyer1: ContractAddress = 01456.try_into().unwrap();
    let (new_orb_address, orbInvocationAddress) = invokeHash();
    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };

    let mut spy = spy_events(SpyOn::One(orbInvocationAddress));

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.flag_response(new_orb_address, 1, 1);
    spy
    .assert_emitted(
        @array![
            (
                orbInvocationAddress,
                ORBInvocationRegistry::Event::ResponseFlagging(
                    ORBInvocationRegistry::ResponseFlagging {
                        orb_address: new_orb_address, invocation_id: 1, flager: buyer1
                    }
                )
            )
        ]
    );
    stop_cheat_caller_address(orbInvocationAddress);
}

#[test]
fn test_rate_positive_response() {
    let buyer1: ContractAddress = 01456.try_into().unwrap();
    let (new_orb_address, orbInvocationAddress) = invokeHash();
    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };

    let mut spy = spy_events(SpyOn::One(orbInvocationAddress));

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.rate_positive_reponse(new_orb_address, 1, 1);

    spy
    .assert_emitted(
        @array![
            (
                orbInvocationAddress,
                ORBInvocationRegistry::Event::PositiveRating(
                    ORBInvocationRegistry::PositiveRating {
                        orb_address: new_orb_address,
                        invocation_id: 1,
                        usage_level: 001,
                        user_satisfaction: 001,
                    }
                )
            )
        ]
    );
    stop_cheat_caller_address(orbInvocationAddress);
}

#[test]
#[should_panic(expected: ('ALREADY_FLAGGED',))]
fn test_rate_positive_response_panic() {
    let buyer1: ContractAddress = 01456.try_into().unwrap();
    let (new_orb_address, orbInvocationAddress) = invokeHash();
    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };
    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.flag_response(new_orb_address, 1, 1);
    stop_cheat_caller_address(orbInvocationAddress);

  
    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.rate_positive_reponse(new_orb_address, 1, 1);
    stop_cheat_caller_address(orbInvocationAddress);
}

#[test]
#[should_panic(expected:('POSITIVE_RATED',))]
fn test_flag_response_panic(){
    let buyer1: ContractAddress = 01456.try_into().unwrap();
    let (new_orb_address, orbInvocationAddress) = invokeHash();
    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.rate_positive_reponse(new_orb_address, 1, 1);
    stop_cheat_caller_address(orbInvocationAddress);

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    orbInvocationDispatcher.flag_response(new_orb_address, 1, 1);
    stop_cheat_caller_address(orbInvocationAddress);
}


fn tip_invocation()->(ContractAddress, ContractAddress, ContractAddress){
    let owner: ContractAddress = 123.try_into().unwrap();
    let buyer1: ContractAddress = 01456.try_into().unwrap();
   

    let tokenAddress = deploy_erc20('OrbToken', 'OTK', 18);

    let tokenDispatcher = IERC20Dispatcher { contract_address: tokenAddress };
    
    let newKeeper: ContractAddress = 124.try_into().unwrap();

    let orbInvocationAddress = deploy_orbinvocation_registry(owner);

    let orbInvocationDispatcher = IOrbInvocationRegistryTraitDispatcher {
        contract_address: orbInvocationAddress
    };

    let orb_class = declare("ORB").unwrap();
    let hash: ClassHash = orb_class.class_hash;

    let orb_pond_address = deploy_orbpond_contract(orbInvocationAddress);

    let orbpond_dispatcher = IOrbPondTraitDispatcher { contract_address: orb_pond_address };
    start_cheat_caller_address(orb_pond_address, owner);
    orbpond_dispatcher.register_version(1, hash);
    stop_cheat_caller_address(orb_pond_address);

    start_cheat_caller_address(orb_pond_address, newKeeper);
    let uri:ByteArray =  "qwertyu";
    let new_orb_address = orbpond_dispatcher.create_orb('vinceOrb', 'VOB', uri, 5);

    stop_cheat_caller_address(orb_pond_address);

    start_cheat_caller_address(tokenAddress, buyer1);
    tokenDispatcher.mint(500);
    tokenDispatcher.approve(new_orb_address, 500);
    stop_cheat_caller_address(tokenAddress);

    let orbDispatcher = IOrbTraitDispatcher { contract_address: new_orb_address };

    start_cheat_caller_address(new_orb_address, newKeeper);
    orbDispatcher.set_price(1000);

    orbDispatcher.swear_oath("hellop", 14400, 1440);

    orbDispatcher.start_orb();
    stop_cheat_caller_address(new_orb_address);

    start_cheat_caller_address(new_orb_address, buyer1);

    orbDispatcher.buy_orb(buyer1, 200, tokenAddress, 1);
    stop_cheat_caller_address(new_orb_address);

    // let mut spy = spy_events(SpyOn::One(orbInvocationAddress));

    start_cheat_caller_address(orbInvocationAddress, buyer1);
    start_cheat_block_timestamp(orbInvocationAddress, 20);
    orbInvocationDispatcher.invoke_with_hash("qwerty", new_orb_address, 1);
    stop_cheat_block_timestamp(orbInvocationAddress);
    stop_cheat_caller_address(orbInvocationAddress);

    // // RESPOND 
    start_cheat_caller_address(orbInvocationAddress, newKeeper);
    start_cheat_block_timestamp(orbInvocationAddress, 40);
    orbInvocationDispatcher.respond(1, "qwertqwey", new_orb_address);

    stop_cheat_block_timestamp(orbInvocationAddress);
    stop_cheat_caller_address(orbInvocationAddress);

    // // tip Invocation
    let orbTipJarAddress = deploy_orb_invocation_tipjar(owner);
    let tipjar_dispatcher = OrbInvocationTipJarTraitDispatcher{contract_address:orbTipJarAddress};
    let mut spy = spy_events(SpyOn::One(orbTipJarAddress));
    start_cheat_caller_address(tokenAddress, buyer1);
    tokenDispatcher.approve(orbTipJarAddress, 500);
    stop_cheat_caller_address(tokenAddress);
  
    start_cheat_caller_address(orbTipJarAddress, buyer1);
    tipjar_dispatcher.tip_invocation(new_orb_address, tokenAddress, "qwerty", 100);

    spy
    .assert_emitted(
        @array![
            (
                orbTipJarAddress,
                ORB_invocation_tipJar::Event::TipDeposit(
                    ORB_invocation_tipJar::TipDeposit {
                        orb_address: new_orb_address, invocation_hash: "qwerty", tipper: buyer1
                    }
                )
            )
        ]
    );
    stop_cheat_caller_address(orbTipJarAddress);
    (orbTipJarAddress, new_orb_address, tokenAddress)

}

#[test]
fn test_tip_invocation(){
    tip_invocation();
}

#[test]
fn claim_tips_for_invocation(){
    let (orbTipJarAddress, new_orb_address, tokenAddress) = tip_invocation();
    let tipjar_dispatcher = OrbInvocationTipJarTraitDispatcher{contract_address:orbTipJarAddress};
    let newKeeper: ContractAddress = 124.try_into().unwrap();
  

    start_cheat_caller_address(orbTipJarAddress, newKeeper);
    tipjar_dispatcher.claim_tips_for_invocation(new_orb_address, 1, 20, tokenAddress);
    
    stop_cheat_caller_address(orbTipJarAddress);
}
#[test]
fn test_withdraw_tip(){
    let (orbTipJarAddress, new_orb_address, tokenAddress) = tip_invocation();
    let tipjar_dispatcher = OrbInvocationTipJarTraitDispatcher{contract_address:orbTipJarAddress};
    let buyer1: ContractAddress = 01456.try_into().unwrap();
  

    start_cheat_caller_address(orbTipJarAddress, buyer1);

    tipjar_dispatcher.withdraw_tip("qwerty", new_orb_address, tokenAddress);
    
    stop_cheat_caller_address(orbTipJarAddress);

}