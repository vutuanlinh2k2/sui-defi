#[test_only]
module amm::amm_tests;

use amm::amm;
use amm::constants::{current_version};
use amm::decimal::{Self, eq};
use amm::pair::{Self, Pair, LPCoin, minimum_liquidity};
use amm::registry::{Self, Registry};
use amm::utils::{Self};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::test_scenario::{Scenario, begin, end, return_shared, return_to_sender};

const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

public struct FSUI has store {}
public struct USDT has store {}

// === TEST FUNCTIONS ===

// TODO: A test everything function? 

// CREATE PAIR
#[test]
fun create_pair_successfully () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let fsui_amount  = 10_000_000_000;
    let usdt_amount = 40_000_000_000;

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<FSUI>(fsui_amount, ALICE, &mut test);
        deposit_coin_to_address<USDT>(usdt_amount, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    let pair_id = {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);


        let id = amm::create_pair_and_mint_lp_coin<FSUI, USDT> (
            &mut registry,
            test.take_from_sender<Coin<FSUI>>(),
            test.take_from_sender<Coin<USDT>>(),
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);

        id
    };

    test.next_tx(ALICE);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<FSUI, USDT>().contains(&current_version()));
        assert!(pair.price_last_update_timestamp_s<FSUI, USDT>() == 0);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<FSUI, USDT>();
        assert!(eq(price_a_cumulative_last, decimal::from(0)));
        assert!(eq(price_b_cumulative_last, decimal::from(0)));
        assert!(pair.k_last<FSUI, USDT>() == (fsui_amount as u128) * (usdt_amount as u128));
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<FSUI, USDT>();
        assert!(reserve_a_amount == fsui_amount);
        assert!(reserve_b_amount == usdt_amount);
        assert!(pair.fees_amount<FSUI, USDT>() == 0);
        assert!(pair.lp_locked_amount<FSUI, USDT>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<FSUI, USDT>();
        assert!(lp_supply == (std::u128::sqrt((fsui_amount as u128) * (usdt_amount as u128))) as u64);
        let lp_coin = test.take_from_address<Coin<LPCoin<FSUI, USDT>>>(ALICE);
        assert!(coin::value(&lp_coin) == lp_supply - minimum_liquidity());

        return_shared(pair);
        test.return_to_sender(lp_coin);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = pair::EMinimumAmountOfCoinsToProvideNotMet)]
fun create_pair_failed_amount_zero () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let fsui_amount  = 0;
    let usdt_amount = 0;

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<FSUI>(fsui_amount, ALICE, &mut test);
        deposit_coin_to_address<USDT>(usdt_amount, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);
    
        amm::create_pair_and_mint_lp_coin<FSUI, USDT> (
            &mut registry,
            test.take_from_sender<Coin<FSUI>>(),
            test.take_from_sender<Coin<USDT>>(),
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = amm::EDeadlinePassed)]
fun create_pair_failed_deadline_passed () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let fsui_amount  = 10_000_000_000;
    let usdt_amount = 40_000_000_000;

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<FSUI>(fsui_amount, ALICE, &mut test);
        deposit_coin_to_address<USDT>(usdt_amount, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    {
        let mut clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);

        clock.set_for_testing(1);
    
        amm::create_pair_and_mint_lp_coin<FSUI, USDT> (
            &mut registry,
            test.take_from_sender<Coin<FSUI>>(),
            test.take_from_sender<Coin<USDT>>(),
            clock.timestamp_ms() - 1,
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = utils::EIdenticalCoins)]
fun create_pair_failed_identical_coins () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let usdt_amount = 10_000_000_000;

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<USDT>(usdt_amount, ALICE, &mut test);
        deposit_coin_to_address<USDT>(usdt_amount, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);
    
        amm::create_pair_and_mint_lp_coin<USDT, USDT> (
            &mut registry,
            test.take_from_sender<Coin<USDT>>(),
            test.take_from_sender<Coin<USDT>>(),
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
    };

    test.end();
}

// ADD LIQUIDITY
// fun add_liquidity_and_mint_lp_coin<CoinA, CoinB>(
//     registry: &Registry,
//     pair: &mut Pair,
//     coin_a: Coin<CoinA>,
//     coin_b: Coin<CoinB>,
//     amount_a_min: u64,
//     amount_b_min: u64,
//     deadline_timestamp_ms: u64,
//     clock: &Clock,
//     ctx: &mut TxContext,  
// )
/* 
    pass
    deadline pass
    identical coins
    amount_0
    wrong version
    amount too little (mint amount = 0)
    amount a or b min not met
    fees_on vs fees_off (because this update k_last)
    reserve_amount = 0
 */

// REMOVE LIQUIDITY
// fun remove_liquidity_and_burn_lp_coin<CoinA, CoinB>(
//     registry: &Registry,
//     pair: &mut Pair,
//     coin_lp: Coin<LPCoin<CoinA, CoinB>>,
//     amount_a_min: u64,
//     amount_b_min: u64,
//     deadline_timestamp_ms: u64,
//     clock: &Clock,
//     ctx: &mut TxContext,
// )
/* 
    pass
    deadline_pass
    identical coins
    amount_0
    wrong version
    wrong lp token
    too little amount to withdraw (burn amount = 0)
    amount a or b min not met
    fees_on vs fees_off
    reserve_amount = 0
 */

// SWAP EXACT COINS FOR COINS
/* 
    pass
    deadline_pass
    wrong version
    wrong coins to swap 
    min amount not met
    right order vs wrong order
    amount = 0
    reserve_amount = 0
 */

// SWAP COINS FOR EXACT COINS
/* 
    pass
    deadline_pass
    wrong version
    wrong coins to swap 
    min amount not met
    right order vs wrong order
    amount = 0
    reserve_amount = 0
 */


// === TEST-ONLY FUNCTIONS ===

#[test_only]
fun setup_test(owner: address, test: &mut Scenario): ID {
    test.next_tx(owner);
    share_clock(test);
    share_registry_for_testing(test)
}

#[test_only]
fun share_clock(test: &mut Scenario) {
    test.next_tx(OWNER);
    clock::create_for_testing(test.ctx()).share_for_testing();  
}

#[test_only]
fun share_registry_for_testing(test: &mut Scenario): ID {
    test.next_tx(OWNER);
    registry::test_registry(test.ctx())
}

#[test_only]
fun deposit_coin_to_address<CoinType>(value: u64, recipient: address, test: &mut Scenario) {
    let coin = coin::mint_for_testing<CoinType>(value, test.ctx());
    transfer::public_transfer(coin, recipient);
}