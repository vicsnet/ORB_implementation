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
    fn set_token_uri(ref self: TContractState, new_token_uri: felt252);
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
    //Equivalent to 0.4
    const WEIGHT_USAGE_LEVEL2: i128 = 4;
    //Equivalent to 0.3
    const WEIGHT_SUBSCRIPTION_DEMAND2: i128 = 3;
    //Equivalent to 0.3
    const WEIGHT_USER_SATISFACTION2: i128 = 3;

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
        // List the Orb
        orb_status: bool,
        // Response Period: time period in which the keeper promises to repond to an invocation.
        // Penalty: premium price will reduce if not fufiled
        response_period: u256,
        // totalSupply of the fractioned NFT token
        total_supply: u256,
        // fractioned token bought
        token_owned: u256,
        // token Owned last id
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

    #[constructor]
    fn constructor(ref self: ContractState, name_: felt252, symbol_: felt252, total_supply_: u256) {
        assert(total_supply_ <= MAX_SUPPLY, 'SUPPLY_EXCEED_MAX');
        assert(total_supply_ >= 1, 'INCREASE_SUPPLY');
        self.name.write(name_);
        self.symbol.write(symbol_);
        self.total_supply.write(total_supply_);
    }

    #[abi(embed_v0)]
    impl ERC721_metadata of super::IERC721_metadata<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self.name.read()
        }
        fn symbol(self: @ContractState) -> felt252 {
            self.symbol.read()
        }

        fn token_uri(self: @ContractState) -> felt252 {
            self.token_URI.read()
        }
    }

    #[abi(embed_v0)]
    impl ERC721 of super::IERC_721<ContractState> {
        fn balance_of(self: @ContractState, owner_: ContractAddress) -> u256 {
            // let caller = get_caller_address();
            1
        }
        fn owner_of(self: @ContractState, token_id_: u256) -> ContractAddress {
            let zero_address = contract_address_const::<0>();

            if (token_id_ != token_id_) {
                zero_address
            } else {
                self.owner.read()
            }
        }
        fn safe_transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            print!("NOT_SUPPORTED");
        }
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256
        ) {
            print!("NOT_SUPPORTED");
        }
        fn approve(ref self: ContractState, approved: ContractAddress, token_id: u256) {
            print!("NOT_SUPPORTED");
        }
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            print!("NOT_SUPPORTED");
        }
        fn get_apporved(self: @ContractState, token_id: u256) -> ContractAddress {
            print!("NOT_SUPPORTED");
            get_contract_address()
        }
        fn is_approved_for_all(
            self: @ContractState, owner_: ContractAddress, operator: ContractAddress
        ) -> bool {
            print!("NOT_SUPPORTED");
            false
        }
        fn set_token_uri(ref self: ContractState, new_token_uri: felt252) {
            let caller = get_caller_address();
            let is_owner = self.only_owner(caller);
            assert(is_owner == true, 'NOT_ORB_CREATOR');
            self.token_URI.write(new_token_uri);
        }
    }
    // @notice get the total fractioned supply 
    #[external(v0)]
    fn get_total_supply(self: @ContractState) -> u256 {
        self.total_supply.read()
    }
    /// @notice Checks the tokenbalance of the caller on the contract
    #[external(v0)]
    fn token_balance_of(self: @ContractState, owner_: ContractAddress) -> u256 {
        self.balances.read(owner_)
    }
    // @notice set the total Orb price
    #[external(v0)]
    fn set_price(ref self: ContractState, price_: u256) {
        let caller = get_caller_address();
        self.only_owner(caller);
        self.set_price_(price_);
    }
    // @notice activate the Orb
    #[external(v0)]
    fn start_orb(ref self: ContractState) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        self.orb_status.write(true);
    }

    // @notice swear Orb Oath
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

    }

    // Allows the Orb creator to extend the honoredUntil date
    #[external(v0)]
    fn extend_honored_until(ref self: ContractState, new_honored_until: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_honored_until > self.honored_until.read(), 'HONORED_DATE_DISAPPROVED');
        self.honored_until.write(new_honored_until);
    }
    // @notice Allows the Orb creator to set the new cooldown duration period
    #[external(v0)]
    fn set_cool_down(ref self: ContractState, new_cooldown: u256, new_flagging_period: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_cooldown < COOLDOWN_MAXIMUM_DURATION, 'COOLDOWN_EXCEED_DURATION');
        self.cooldown.write(new_cooldown);
        self.flagging_period.write(new_flagging_period);
    }

    // @notice Allows the Orb creator to set the new cleartext maximum length.
    #[external(v0)]
    fn set_clear_text_maximum_length(ref self: ContractState, new_clear_text: u256) {
        let caller = get_caller_address();
        let is_owner = self.only_owner(caller);
        assert(is_owner == true, 'NOT_ORB_CREATOR');
        assert(new_clear_text > 0, 'INVALID_TEXT_MAXIMUM_LENGTH');
        self.clear_text_maximum_length.write(new_clear_text);
    }

    // @notice buy a part of the fractioned Orb
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
    }

    // @notice buy premium when orb is not active
    // @param token_id_: Id of the fractioned token
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
    }

    // @external list non active premium

    // @notice deposit fund into the contract
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
    }
    //@notice withdrawAll your fund from the contract
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
    }
    // @notice Withdraw fund from the contract
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
    }

    //@notice relinquish the orb: give up your Orb
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
    }
    // @notice get the balance of the caller
    #[external(v0)]
    fn my_fractioned_balance(self: @ContractState, owner_: ContractAddress) -> u256 {
        self.fractioned_balances.read(owner_)
    }

    #[external(v0)]
    fn get_subscription_remaining_time(self: @ContractState, token_id_: u256) -> u256 {
        self.subscription_time.read(token_id_)
    }

    #[external(v0)]
    fn my_last_invocation_time(self: @ContractState, token_id_: u256) -> u256 {
        self.last_invocation.read(token_id_)
    }

    #[external(v0)]
    fn get_invocation_period(self: @ContractState) -> u256 {
        self.cooldown.read()
    }

    //@notice setLast invocation time
    // TOBELOOKEDAT
    #[external(v0)]
    fn set_last_invocation_time(ref self: ContractState, token_id_: u256, owner_: ContractAddress) {
        assert(self.fractioned_balances.read(owner_) > 0, 'NO_TOKEN');
        assert(self.fractioned_token_id_owner.read(token_id_) == owner_, 'NOT_OWNER');
        let current_time: u256 = get_block_timestamp().try_into().unwrap();
        self.last_invocation.write(token_id_, current_time);
    }

    // @notice set premimum data by the user
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

    // @notice set premium data by owner
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


    //@notice foreclose
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
    }

    #[external(v0)]
    fn get_owner(self: @ContractState, owner_: ContractAddress) -> bool {
        self.only_owner(owner_)
    }

    #[external(v0)]
    fn get_flagging_period(self: @ContractState) -> u256 {
        self.flagging_period.read()
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn only_owner(self: @ContractState, owner_: ContractAddress) -> bool {
            if (owner_ != self.owner.read()) {
                false
            } else {
                true
            }
        }

        // @notice set the total orb Price
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
    // @notice show non active premium
    // fn get_non_active_orb()->
    }
}
