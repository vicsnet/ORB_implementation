use core::traits::TryInto;
use core::result::ResultTrait;
use starknet::ContractAddress;

use snforge_std::{
    declare, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
    cheat_caller_address, spy_events, EventSpy, SpyOn, EventAssertions, EventFetcher,
    cheat_block_timestamp, CheatSpan, start_cheat_block_timestamp, stop_cheat_block_timestamp
};
use orbland::orb::{
    IOrbTraitDispatcher, IOrbTraitDispatcherTrait, IERC_721Dispatcher, IERC_721DispatcherTrait,
    IERC_165Dispatcher, IERC_165DispatcherTrait, IERC721_metadataDispatcher,
    IERC721_metadataDispatcherTrait, ORB
};
// IERC20Dispatcher, IERC20DispatcherTrait
use orbland::mock_erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

fn deploy_contract(
    name_: felt252,
    symbol_: felt252,
    total_supply_: u256,
    token_uri_: felt252,
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
    start_cheat_caller_address(contract_address, 1265.try_into().unwrap());

    let (deployedContract, _) = contract.deploy(@calldata).unwrap();
    stop_cheat_caller_address(contract_address);

    deployedContract
}
fn get_deployed_address() -> ContractAddress {
    let deployer: ContractAddress = 123.try_into().unwrap();
    let deployed_address = deploy_contract('Vince', 'VIN', 4, '123dfedes', deployer);
    deployed_address
}

#[test]
fn test_ERC721_metadata() {
    let contract_address = get_deployed_address();

    let erc721Dispatcher = IERC721_metadataDispatcher { contract_address };
    let name = erc721Dispatcher.name();
    let symbol = erc721Dispatcher.symbol();
    let token_uri = erc721Dispatcher.token_uri();
    assert(name == 'Vince', 'wrong Name');
    assert(name != 'VinceD', 'Right Name');
    assert(symbol == 'VIN', 'Wrong symbol');
    assert(symbol != 'VIND', 'Right Symbol');
    assert(token_uri == '123dfedes', 'Wrong URI');
    assert(token_uri != '12fedes', 'Right URI');
}
#[test]
fn test_erc721_balance() {
    let contract_address = get_deployed_address();
    let erc721Dispatcher = IERC_721Dispatcher { contract_address };
    let deployer: ContractAddress = 123.try_into().unwrap();
    let caller: ContractAddress = 123567.try_into().unwrap();
    let balance_of = erc721Dispatcher.balance_of(deployer);
    assert(balance_of == 1, 'WRONG DEPLOYER ADDRESS');
    let balance_of_caller = erc721Dispatcher.balance_of(caller);
    assert(balance_of_caller == 0, 'Wrong balance');
}
#[test]
fn test_total_supply() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let supply = orbDispatcher.get_total_supply();
    assert(supply == 4, 'WRONG SUPPLY');

    let owner: ContractAddress = 123567.try_into().unwrap();
    let token_balance_of = orbDispatcher.token_balance_of(owner);
    assert(token_balance_of == 0, 'Wrong balance');

    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    orbDispatcher.set_price(1000);
    stop_cheat_caller_address(contract_address);
}
#[test]
#[should_panic(expected: ('OATH_NOT_SWORN',))]
fn test_start_orb_panic() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    orbDispatcher.start_orb();
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_swear_oath() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let mut spy = spy_events(SpyOn::One(contract_address));
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    let data_hash: ByteArray = "12345";
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::OathSwearing(
                        ORB::OathSwearing {
                            oath_hash: data_hash, honored_until: 20, response_period: 2
                        }
                    )
                )
            ]
        );

    stop_cheat_caller_address(contract_address);
}
#[test]
#[should_panic(expected: ('NOT_ORB_CREATOR',))]
fn test_start_orb_panic_not_creator() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    stop_cheat_caller_address(contract_address);
    orbDispatcher.start_orb();
}
#[test]
fn test_start_orb() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.start_orb();
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('OATH_NOT_SWORN',))]
fn test_extend_honored_until_panic() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    orbDispatcher.extend_honored_until(50);
    stop_cheat_caller_address(contract_address);
}
#[test]
fn test_extend_honored_until() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let mut spy = spy_events(SpyOn::One(contract_address));
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.extend_honored_until(50);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::HonoredUntilUpdate(
                        ORB::HonoredUntilUpdate {
                            previous_honored_until: 20, new_honored_until: 50
                        }
                    )
                )
            ]
        );
    stop_cheat_caller_address(contract_address);
// cheat_block_timestamp(contract_address)
}
#[test]
fn test_cooldown() {
    let contract_address = get_deployed_address();
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let mut spy = spy_events(SpyOn::One(contract_address));
    let caller: ContractAddress = 123.try_into().unwrap();
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.set_cool_down(10, 5);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::CooldownUpdate(
                        ORB::CooldownUpdate {
                            previous_cooldown: 0,
                            new_cooldown: 10,
                            previous_flagging_period: 0,
                            new_flagging_period: 5,
                        }
                    )
                )
            ]
        );

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_buy_orb() {
    let contract_address = get_deployed_address();
    let buyer: ContractAddress = 1265.try_into().unwrap();
    let caller: ContractAddress = 123.try_into().unwrap();

    let erc20_address = deploy_erc20('orbTo', 'OBT', 18);
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let erc20Dispatcher = IERC20Dispatcher { contract_address: erc20_address };
    let mut spy = spy_events(SpyOn::One(contract_address));
    let balance_erc20 = erc20Dispatcher.balance_of(buyer);
    println!("{} balance of buyer", balance_erc20);
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.set_cool_down(10, 5);
    orbDispatcher.set_price(1000);
    orbDispatcher.start_orb();
    stop_cheat_caller_address(contract_address);
    start_cheat_caller_address(erc20_address, buyer);
    erc20Dispatcher.mint(5000);
    erc20Dispatcher.approve(contract_address, 600);
    stop_cheat_caller_address(erc20_address);
    start_cheat_caller_address(contract_address, buyer);
    orbDispatcher.buy_orb(buyer, 250, erc20_address, 1);

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::BuyOrb(
                        ORB::BuyOrb {
                            buyer_address: buyer, amount_: 250, fractioned_unit_: 1, token_id: 1,
                        }
                    )
                )
            ]
        );
    stop_cheat_caller_address(contract_address);
}

// price need to be reviewed when testing invocation
#[test]
fn test_buy_nonactive_orb() {
    let contract_address = get_deployed_address();
    let erc20_address = deploy_erc20('orbTo', 'OBT', 18);
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let erc20Dispatcher = IERC20Dispatcher { contract_address: erc20_address };
    let buyer: ContractAddress = 1265.try_into().unwrap();
    let buyer2: ContractAddress = 12685.try_into().unwrap();
    let caller: ContractAddress = 123.try_into().unwrap();
    let mut spy = spy_events(SpyOn::One(contract_address));
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.set_cool_down(10, 5);
    orbDispatcher.set_price(1000);
    orbDispatcher.start_orb();
    stop_cheat_caller_address(contract_address);
    start_cheat_caller_address(erc20_address, buyer);
    erc20Dispatcher.mint(5000);
    erc20Dispatcher.approve(contract_address, 600);

    stop_cheat_caller_address(erc20_address);
    start_cheat_caller_address(erc20_address, buyer2);
    erc20Dispatcher.mint(10000);
    erc20Dispatcher.approve(contract_address, 1000);
    stop_cheat_caller_address(erc20_address);
    start_cheat_caller_address(contract_address, buyer);
    orbDispatcher.buy_orb(buyer, 250, erc20_address, 1);
    stop_cheat_caller_address(contract_address);
    start_cheat_caller_address(contract_address, buyer2);
    start_cheat_block_timestamp(contract_address, 10000);
    orbDispatcher.buy_orb(buyer2, 250, erc20_address, 1);
    stop_cheat_caller_address(contract_address);
    stop_cheat_block_timestamp(contract_address);
    start_cheat_block_timestamp(contract_address, 10000);
    start_cheat_caller_address(erc20_address, buyer2);
    erc20Dispatcher.mint(10000);
    erc20Dispatcher.approve(contract_address, 600);
    stop_cheat_caller_address(erc20_address);
    start_cheat_caller_address(contract_address, buyer2);
    orbDispatcher.buy_nonactive_orb(1, 250, erc20_address);

    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::NonActivePurchase(
                        ORB::NonActivePurchase {
                            new_owner: buyer2, previous_owner: buyer, amount_: 250, token_id: 1
                        }
                    )
                )
            ]
        );
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_relinquish() {
    let contract_address = get_deployed_address();
    let buyer: ContractAddress = 1265.try_into().unwrap();
    let caller: ContractAddress = 123.try_into().unwrap();
    let mut spy = spy_events(SpyOn::One(contract_address));
    let erc20_address = deploy_erc20('orbTo', 'OBT', 18);
    let orbDispatcher = IOrbTraitDispatcher { contract_address };
    let erc20Dispatcher = IERC20Dispatcher { contract_address: erc20_address };
    let balance_erc20 = erc20Dispatcher.balance_of(buyer);
    println!("{} balance of buyer", balance_erc20);
    start_cheat_caller_address(contract_address, caller);
    let oath_hash: ByteArray = "12345";
    orbDispatcher.swear_oath(oath_hash, 20, 2);
    orbDispatcher.set_cool_down(10, 5);
    orbDispatcher.set_price(1000);
    orbDispatcher.start_orb();
    stop_cheat_caller_address(contract_address);
    start_cheat_caller_address(erc20_address, buyer);
    erc20Dispatcher.mint(5000);
    erc20Dispatcher.approve(contract_address, 600);
    stop_cheat_caller_address(erc20_address);
    start_cheat_caller_address(contract_address, buyer);
    orbDispatcher.buy_orb(buyer, 250, erc20_address, 1);
    stop_cheat_caller_address(contract_address);
    start_cheat_block_timestamp(contract_address, 10000);
    start_cheat_caller_address(contract_address, buyer);
    let fractioned_balance = orbDispatcher.my_fractioned_balance(buyer);
    assert(fractioned_balance == 1, 'INCORRECT_BALANCE');
    orbDispatcher.relinquish(1);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ORB::Event::OrbReliquish(ORB::OrbReliquish { orb_owner: buyer, token_id: 1 })
                )
            ]
        );
    stop_cheat_block_timestamp(contract_address);
    stop_cheat_block_timestamp(contract_address);
}
