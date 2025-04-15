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
use sui::test_utils;

const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const INITIAL_SUI_RESERVE_AMOUNT: u64 = 10_000_000_000; // 10 SUI
const INITIAL_USDC_RESERVE_AMOUNT: u64 = 40_000_000_000; // 40 USDC

public struct SUI has store {}
public struct USDC has store {}

// === TEST FUNCTIONS ===

// CREATE PAIR
#[test]
fun create_pair_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id,
        INITIAL_SUI_RESERVE_AMOUNT,
        INITIAL_USDC_RESERVE_AMOUNT,  
        &mut test
    );

    test.next_tx(ALICE);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<SUI, USDC>().contains(&current_version()));
        assert!(pair.price_last_update_timestamp_s<SUI, USDC>() == 0);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<SUI, USDC>();
        assert!(eq(price_a_cumulative_last, decimal::from(0)));
        assert!(eq(price_b_cumulative_last, decimal::from(0)));
        assert!(pair.k_last<SUI, USDC>() == (INITIAL_SUI_RESERVE_AMOUNT as u128) * (INITIAL_USDC_RESERVE_AMOUNT as u128));
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == INITIAL_SUI_RESERVE_AMOUNT);
        assert!(reserve_b_amount == INITIAL_USDC_RESERVE_AMOUNT);
        assert!(pair.fees_amount<SUI, USDC>() == 0);
        assert!(pair.lp_locked_amount<SUI, USDC>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        assert!(lp_supply == (std::u128::sqrt((INITIAL_SUI_RESERVE_AMOUNT as u128) * (INITIAL_USDC_RESERVE_AMOUNT as u128))) as u64);
        let lp_coin = test.take_from_address<Coin<LPCoin<SUI, USDC>>>(ALICE);
        assert!(coin::value(&lp_coin) == lp_supply - minimum_liquidity());

        return_shared(pair);
        test.return_to_sender(lp_coin);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = pair::EInsufficientProvidedAmount)]
fun create_pair_failed_insufficient_amount () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let sui_amount  = 2;
    let usdc_amount = 8; // sqrt(8*2) = 4, < MINIMUM_LIQUIDITY (10)

    setup_pair_created_by_alice(
        registry_id,
        sui_amount,
        usdc_amount,  
        &mut test
    );

    test.end();
}

#[test]
#[expected_failure(abort_code = amm::EDeadlinePassed)]
fun create_pair_failed_deadline_passed () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<SUI>(INITIAL_SUI_RESERVE_AMOUNT, ALICE, &mut test);
        deposit_coin_to_address<USDC>(INITIAL_USDC_RESERVE_AMOUNT, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    {
        let mut clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);

        clock.set_for_testing(1);
    
        amm::create_pair_and_mint_lp_coin<SUI, USDC> (
            &mut registry,
            test.take_from_sender<Coin<SUI>>(),
            test.take_from_sender<Coin<USDC>>(),
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

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<USDC>(INITIAL_USDC_RESERVE_AMOUNT, ALICE, &mut test);
        deposit_coin_to_address<USDC>(INITIAL_USDC_RESERVE_AMOUNT, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);
    
        amm::create_pair_and_mint_lp_coin<USDC, USDC> (
            &mut registry,
            test.take_from_sender<Coin<USDC>>(),
            test.take_from_sender<Coin<USDC>>(),
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
    };

    test.end();
}

// #[test]
// fun create_pair_failed_already_exists

// ADD LIQUIDITY
#[test]
fun add_liquidity_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(10_000_000_000, BOB, &mut test);
        deposit_coin_to_address<USDC>(5_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let mut sui_coin = test.take_from_sender<Coin<SUI>>();
        
        clock.set_for_testing(10_000);

        amm::add_liquidity_and_mint_lp_coin<SUI, USDC>(
            &registry,
            &mut pair,
            coin::split(&mut sui_coin, 1_000_000_000, test.ctx()),
            test.take_from_sender<Coin<USDC>>(),
            800_000_000,
            4_000_000_000,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
        test.return_to_sender(sui_coin);
    };

    test.next_tx(BOB);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<SUI, USDC>().contains(&current_version()));
        assert!(pair.price_last_update_timestamp_s<SUI, USDC>() == 10);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<SUI, USDC>();
        assert!(price_a_cumulative_last.to_scaled_val() == 40_000_000_000); // 10 (secs) * 4 * FLOAT_SCALING (10^9)
        assert!(price_b_cumulative_last.to_scaled_val() == 2_500_000_000); // 10 (secs) * 0.25 * FLOAT_SCALING (10^9)
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == 11_000_000_000);
        assert!(reserve_b_amount == 44_000_000_000);
        assert!(pair.k_last<SUI, USDC>() == (reserve_a_amount as u128) * (reserve_b_amount as u128));
        assert!(pair.fees_amount<SUI, USDC>() == 0);
        assert!(pair.lp_locked_amount<SUI, USDC>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        assert!(lp_supply == (std::u128::sqrt((reserve_a_amount as u128) * (reserve_b_amount as u128))) as u64);

        // Check user's coin balances
        let sui_coin = test.take_from_address<Coin<SUI>>(BOB);
        let usdc_coin = test.take_from_address<Coin<USDC>>(BOB);
        let lp_coin = test.take_from_address<Coin<LPCoin<SUI, USDC>>>(BOB);
        assert!(coin::value(&sui_coin) == 9_000_000_000); // provide 1 SUI, got 9 (10-1) left
        assert!(coin::value(&usdc_coin) == 1_000_000_000); // provide 4 USDC, got 1 (5-1) left
        assert!(coin::value(&lp_coin) == 2_000_000_000);

        return_shared(pair);
        test.return_to_sender(sui_coin);
        test.return_to_sender(usdc_coin);
        test.return_to_sender(lp_coin);
    };

    test.end();
}

// #[test]
// fun add_liquidity_failed_deadline_passes (skip)

#[test]
#[expected_failure(abort_code = pair::EInsufficientProvidedAmount)]
fun add_liquidity_failed_insufficient_amount_provided() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(0, BOB, &mut test);
        deposit_coin_to_address<USDC>(100_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        
        clock.set_for_testing(10_000);

        amm::add_liquidity_and_mint_lp_coin<SUI, USDC>(
            &registry,
            &mut pair,
            test.take_from_sender<Coin<SUI>>(),
            test.take_from_sender<Coin<USDC>>(),
            800_000_000,
            4_000_000_000,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = pair::EMinimumAmountOfCoinsToProvideNotMet)]
fun add_liquidity_failed_minimum_not_met() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(1_000_000_000, BOB, &mut test);
        deposit_coin_to_address<USDC>(5_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        
        clock.set_for_testing(10_000);

        amm::add_liquidity_and_mint_lp_coin<SUI, USDC>(
            &registry,
            &mut pair,
            test.take_from_sender<Coin<SUI>>(),
            test.take_from_sender<Coin<USDC>>(),
            800_000_000,
            4_500_000_000, // > 1_000_000_000 * 4
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
    };

    test.end();
}

#[test]
fun remove_liquidity_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );
    let lp_burn_amount: u64 = 1_000_000_000;

    test.next_tx(ALICE);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        clock.set_for_testing(10_000);

        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        let mut lp_coin = test.take_from_sender<Coin<LPCoin<SUI, USDC>>>();

        assert!(coin::value(&lp_coin) == lp_supply - minimum_liquidity());

        amm::remove_liquidity_and_burn_lp_coin<SUI,USDC> (
            &registry,
            &mut pair,
            coin::split(&mut lp_coin, lp_burn_amount, test.ctx()),
            500_000_000,
            2_000_000_000,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
        test.return_to_sender(lp_coin);
    };

    test.next_tx(ALICE);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<SUI, USDC>().contains(&current_version()));
        assert!(pair.price_last_update_timestamp_s<SUI, USDC>() == 10);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<SUI, USDC>();
        assert!(price_a_cumulative_last.to_scaled_val() == 40_000_000_000); // 10 (secs) * 4 * FLOAT_SCALING (10^9)
        assert!(price_b_cumulative_last.to_scaled_val() == 2_500_000_000); // 10 (secs) * 0.25 * FLOAT_SCALING (10^9)
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == 9_500_000_000); // reserve_amount - lp_burn_amount * lp_supply / reserve_amount
        assert!(reserve_b_amount == 38_000_000_000); // reserve_amount - lp_burn_amount * lp_supply / reserve_amount
        assert!(pair.k_last<SUI, USDC>() == (reserve_a_amount as u128) * (reserve_b_amount as u128));
        assert!(pair.fees_amount<SUI, USDC>() == 0);
        assert!(pair.lp_locked_amount<SUI, USDC>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        assert!(lp_supply == 19_000_000_000); // (initial 20_000_000_000) - 1_000_000_000

        // Check user's coin balances
        let sui_coin = test.take_from_address<Coin<SUI>>(ALICE);
        let usdc_coin = test.take_from_address<Coin<USDC>>(ALICE);
        let lp_coin = test.take_from_address<Coin<LPCoin<SUI, USDC>>>(ALICE);
        assert!(coin::value(&sui_coin) == 500_000_000); // provide 1 SUI, got 9 (10-1) left
        assert!(coin::value(&usdc_coin) == 2_000_000_000); // provide 4 USDC, got 1 (5-1) left
        assert!(coin::value(&lp_coin) == 18_999_999_990); // 20_000_000_000 - locked value - 1_000_000_000

        return_shared(pair);
        test.return_to_sender(sui_coin);
        test.return_to_sender(usdc_coin);
        test.return_to_sender(lp_coin);
    };

    test.end();
}

// #[test]
// fun remove_liquidity_failed_deadline_passes (skip)

#[test]
#[expected_failure(abort_code = pair::EInsufficientLPCoinAmountBurned)]
fun remove_liquidity_failed_insufficient_amount_burned() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(ALICE);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        clock.set_for_testing(10_000);
        let mut lp_coin = test.take_from_sender<Coin<LPCoin<SUI, USDC>>>();

        amm::remove_liquidity_and_burn_lp_coin<SUI,USDC> (
            &registry,
            &mut pair,
            coin::split(&mut lp_coin, 0, test.ctx()),
            0,
            0,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
        test.return_to_sender(lp_coin);
    };

    test.end();

}

#[test]
#[expected_failure(abort_code = pair::EMinimumAmountOfCoinsToWithdrawNotMet)]
fun remove_liquidity_failed_minimum_not_met() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );
    let lp_burn_amount: u64 = 1_000_000_000;

    test.next_tx(ALICE);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        clock.set_for_testing(10_000);
        let mut lp_coin = test.take_from_sender<Coin<LPCoin<SUI, USDC>>>();

        amm::remove_liquidity_and_burn_lp_coin<SUI,USDC> (
            &registry,
            &mut pair,
            coin::split(&mut lp_coin, lp_burn_amount, test.ctx()),
            500_000_001,
            2_000_000_000,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
        test.return_to_sender(lp_coin);
    };

    test.end();
}

// #[test]
// #[expected_failure]
// fun remove_liquidity_failed_wrong_tokens (skip)

// #[test]
// fun remove_liquidity_all - still got some left due to locked lp coin (skip)

// SWAP EXACT COINS FOR COINS

#[test]
fun swap_exact_coins_for_coins_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(10_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let mut sui_coin = test.take_from_sender<Coin<SUI>>();
        
        clock.set_for_testing(10_000);

        amm::swap_exact_coins_for_coins<SUI, USDC>(
            &mut pair,
            coin::split(&mut sui_coin, 1_000_000_000, test.ctx()),
            0,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(pair);
        test.return_to_sender(sui_coin);
    };

    test.next_tx(BOB);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<SUI, USDC>().contains(&current_version()));
        assert!(pair.price_last_update_timestamp_s<SUI, USDC>() == 0);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<SUI, USDC>();
        assert!(price_a_cumulative_last.to_scaled_val() == 0);
        assert!(price_b_cumulative_last.to_scaled_val() == 0);
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == 11_000_000_000);
        assert!(reserve_b_amount == 36_373_556_425);
        assert!(pair.fees_amount<SUI, USDC>() == 0);
        assert!(pair.lp_locked_amount<SUI, USDC>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        assert!(lp_supply == 20_000_000_000);

        // Check user's coin balances
        let sui_coin = test.take_from_address<Coin<SUI>>(BOB);
        let usdc_coin = test.take_from_address<Coin<USDC>>(BOB);
        // let lp_coin = test.take_from_address<Coin<LPCoin<SUI, USDC>>>(BOB);
        assert!(coin::value(&sui_coin) == 9_000_000_000); // swap 1 SUI, got 9 (10-1) left
        assert!(coin::value(&usdc_coin) == 3_626_443_575);

        return_shared(pair);
        test.return_to_sender(sui_coin);
        test.return_to_sender(usdc_coin);
    };

    test.end();
}

#[test]
fun swap_exact_coins_for_coins__in_reverse_order_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<USDC>(10_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let mut usdc_coin = test.take_from_sender<Coin<USDC>>();
        
        clock.set_for_testing(10_000);

        amm::swap_exact_coins_for_coins<USDC, SUI>(
            &mut pair,
            coin::split(&mut usdc_coin, 4_000_000_000, test.ctx()),
            0,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(pair);
        test.return_to_sender(usdc_coin);
    };

    test.next_tx(BOB);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);

        assert!(pair.allowed_versions<SUI, USDC>().contains(&current_version())); // should I do 
        assert!(pair.price_last_update_timestamp_s<SUI, USDC>() == 0);
        let (price_a_cumulative_last, price_b_cumulative_last) = pair.price_cumulative_last<SUI, USDC>();
        assert!(price_a_cumulative_last.to_scaled_val() == 0);
        assert!(price_b_cumulative_last.to_scaled_val() == 0);
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == 9_093_389_107);
        assert!(reserve_b_amount == 44_000_000_000);
        // std::debug::print(&pair.k_last<SUI, USDC>());
        assert!(pair.fees_amount<SUI, USDC>() == 0);
        assert!(pair.lp_locked_amount<SUI, USDC>() == minimum_liquidity());
        let lp_supply = pair.lp_coin_supply_amount<SUI, USDC>();
        assert!(lp_supply == 20_000_000_000);

        // Check user's coin balances
        let sui_coin = test.take_from_address<Coin<SUI>>(BOB);
        let usdc_coin = test.take_from_address<Coin<USDC>>(BOB);
        assert!(coin::value(&sui_coin) == 906_610_893);
        assert!(coin::value(&usdc_coin) == 6_000_000_000);

        return_shared(pair);
        test.return_to_sender(sui_coin);
        test.return_to_sender(usdc_coin);
    };

    test.end();
}

// Failed Cases: deadline_pass, wrong_coins, min_amount_not_met

// SWAP COINS FOR EXACT COINS (skip)

// ADMIN FUNCTIONS

// fun remove_pair_successfully (skip)

#[test]
fun claim_fees_successfully() {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);
    let pair_id = setup_pair_created_by_alice(
        registry_id, 
        INITIAL_SUI_RESERVE_AMOUNT, 
        INITIAL_USDC_RESERVE_AMOUNT, 
        &mut test
    );

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(10_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let mut sui_coin = test.take_from_sender<Coin<SUI>>();
        
        clock.set_for_testing(10_000);

        amm::swap_exact_coins_for_coins<SUI, USDC>(
            &mut pair,
            coin::split(&mut sui_coin, 1_000_000_000, test.ctx()),
            0,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(pair);
        test.return_to_sender(sui_coin);
    };

    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(10_000_000_000, BOB, &mut test);
        deposit_coin_to_address<USDC>(5_000_000_000, BOB, &mut test);
    };

    test.next_tx(BOB);
    {
        let mut clock = test.take_shared<Clock>();
        let registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let mut sui_coin = test.take_from_sender<Coin<SUI>>();
        
        clock.set_for_testing(10_000);

        amm::add_liquidity_and_mint_lp_coin<SUI, USDC>(
            &registry,
            &mut pair,
            coin::split(&mut sui_coin, 1_000_000_000, test.ctx()),
            test.take_from_sender<Coin<USDC>>(),
            0,
            0,
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);
        return_shared(pair);
        test.return_to_sender(sui_coin);
    };

    test.next_tx(OWNER);
    {
        let mut registry = test.take_shared_by_id<Registry>(registry_id);
        let mut pair = test.take_shared_by_id<Pair>(pair_id);
        let admin_cap = registry::get_admin_cap_for_testing(test.ctx());


        amm::claim_fees<SUI, USDC>(
            &mut registry,
            &mut pair,
            &admin_cap,
            test.ctx()
        );

        return_shared(registry);
        return_shared(pair);
        test_utils::destroy(admin_cap);
    };

    test.next_tx(OWNER);
    {
        let pair = test.take_shared_by_id<Pair>(pair_id);
        assert!(pair.fees_amount<SUI, USDC>() == 0);

        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<SUI, USDC>();
        assert!(reserve_a_amount == 12_000_000_000);
        assert!(reserve_b_amount == 39_680_243_372);

        let lp_fees_coin = test.take_from_sender<Coin<LPCoin<SUI, USDC>>>();
        assert!(&coin::value(&lp_fees_coin) == 454_586);

        assert!(pair.lp_coin_supply_amount<SUI, USDC>() == 21818636403);

        return_shared(pair);
        test.return_to_sender(lp_fees_coin);
    };

    test.end();

}

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

#[test_only]
fun setup_pair_created_by_alice(registry_id: ID, sui_amount: u64, usdc_amount: u64, test: &mut Scenario): ID {
    test.next_tx(OWNER);
    {
        deposit_coin_to_address<SUI>(sui_amount, ALICE, test);
        deposit_coin_to_address<USDC>(usdc_amount, ALICE, test);
    };

    test.next_tx(ALICE);
    let pair_id = {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);


        let id = amm::create_pair_and_mint_lp_coin<SUI, USDC> (
            &mut registry,
            test.take_from_sender<Coin<SUI>>(),
            test.take_from_sender<Coin<USDC>>(),
            clock.timestamp_ms(),
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(registry);

        id
    };

    pair_id
}