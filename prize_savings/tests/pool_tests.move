module prize_savings::pool_tests;

use prize_savings::pool::{Pool, PToken, create_test_pool};
use prize_savings::protocol::{Reserve, create_test_reserve};
use prize_savings::prize_pool_config::{create_test_prize_pool_config};
use prize_savings::test_utils::{deposit_coin_to_address};
use prize_savings::prize_pool::{PrizePool};
use sui::coin::{Coin};
use sui::clock::{Self, Clock};
use sui::random::{Self, Random};
use sui::test_scenario::{Scenario, begin, end, return_shared};
use sui::test_utils::{destroy};

const SYSTEM: address = @0x0;
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

public struct SUI has store {}

#[test]
public fun test_pool() {
    let mut test = begin(OWNER);
    {
        clock::create_for_testing(test.ctx()).share_for_testing(); 
    };

    // Create Reserve
    test.next_tx(OWNER);
    {
        create_test_reserve<SUI>(test.ctx())
    };

    // Create Pool
    test.next_tx(OWNER);
    {
        let clock = test.take_shared<Clock>();
        let reserve = test.take_shared<Reserve<SUI>>();
        let prize_pool_config = create_test_prize_pool_config();

        let pool_id = create_test_pool<SUI>(
            &reserve,
            prize_pool_config,
            &clock,
            test.ctx()
        );

        return_shared(clock);
        return_shared(reserve);

        pool_id
    };

    // Deposit tokens to accounts
    test.next_tx(ALICE);
    {
        deposit_coin_to_address<SUI>(1_000_000_000, ALICE, &mut test);
        deposit_coin_to_address<SUI>(500_000_000, OWNER, &mut test);
        deposit_coin_to_address<SUI>(1_500_000_000, BOB, &mut test);
    };

    // * Alice deposit 1_000_000_000 SUI in 0 sec
    test.next_tx(ALICE);
    deposit(&mut test);

    // * increase reverse balance
    test.next_tx(OWNER);
    {
        let mut reserve = test.take_shared<Reserve<SUI>>();
        let sui = test.take_from_sender<Coin<SUI>>();
        reserve.increase_reserve_balance(sui);
        return_shared(reserve);
    };

    // Add more coin to Alice
    test.next_tx(ALICE);
    {
        deposit_coin_to_address<SUI>(2_000_000_000, ALICE, &mut test);
    };

    // * Alice deposit 2_000_000_000 SUI in 10000 sec
    test.next_tx(ALICE);
    set_timestamp(&test, 10_000);
    test.next_tx(ALICE);
    deposit(&mut test);

    // * Bob deposit 1_500_000_000 SUI in 15000 sec
    test.next_tx(BOB);
    set_timestamp(&test, 15_000);
    test.next_tx(BOB);
    deposit(&mut test);

    // Add more coin to Bob
    test.next_tx(BOB);
    {
        deposit_coin_to_address<SUI>(2_000_000_000, BOB, &mut test);
    };

    // * Bob deposit 2_000_000_000 SUI in 25000 sec
    test.next_tx(BOB);
    set_timestamp(&test, 25_000);
    test.next_tx(BOB);
    deposit(&mut test);

    // * Alice withdraw 1_000_000_000 PToken in 75000 sec
    test.next_tx(ALICE);
    set_timestamp(&test, 75_000);
    test.next_tx(ALICE);
    {
        let mut pool = test.take_shared<Pool<SUI>>();
        let mut reserve = test.take_shared<Reserve<SUI>>();
        let clock = test.take_shared<Clock>();
        let mut p_tokens = test.take_from_sender<Coin<PToken<SUI>>>();

        pool.withdraw_and_burn_p_token(
            &mut reserve, 
            p_tokens.split(1_000_000_000, test.ctx()), 
            test.sender(), 
            &clock, 
            test.ctx()
        );

        return_shared(pool);
        return_shared(reserve);
        return_shared(clock);
        test.return_to_sender(p_tokens);
    };

    test.next_tx(OWNER);
    set_timestamp(&test, 86_400);

    test.next_tx(SYSTEM);
    {
        random::create_for_testing(test.ctx());
    };

    test.next_tx(OWNER);
    {
        let mut pool = test.take_shared<Pool<SUI>>();
        let mut reserve = test.take_shared<Reserve<SUI>>();
        let clock = test.take_shared<Clock>();
        let r = test.take_shared<Random>();

        pool.new_draw_and_prize_pool(&mut reserve, &clock, &r, test.ctx());

        return_shared(pool);
        return_shared(reserve);
        return_shared(clock);
        return_shared(r);
    };

    test.next_tx(OWNER);
    {   
        let pool = test.take_shared<Pool<SUI>>();
        let prize_pool = test.take_shared<PrizePool<SUI>>();
        assert!(prize_pool.pool_id() == object::id(&pool));
        assert!(prize_pool.draw_id() == 1);
        assert!(prize_pool.prize_balances_amount() == 499_999_998); // due to floor
        // assert twab controller (already checked manually)

        return_shared(pool);
        return_shared(prize_pool);
    };

    test.next_tx(ALICE);
    {
        let pool = test.take_shared<Pool<SUI>>();
        assert!(pool.draw_count() == 1);
        assert!(pool.yb_balances_amount() == 3_333_333_334);
        assert!(pool.p_token_supply_amount() == 3_666_666_666);
        assert!(pool.deposited_amount() == 5_000_000_000);
        assert!(pool.current_draw_start_timestamp_s() == 86400);
        // assert prize_pool_config & twab controller (already checked manually)

        return_shared(pool);
    };

    test.end();
}

#[test_only]
fun log_pool(test: & Scenario) {
    let pool = test.take_shared<Pool<SUI>>();
    std::debug::print(&pool);

    return_shared(pool);
}

fun deposit(test: &mut Scenario) {
    let mut pool = test.take_shared<Pool<SUI>>();
    let mut reserve = test.take_shared<Reserve<SUI>>();
    let clock = test.take_shared<Clock>();
    let sui = test.take_from_sender<Coin<SUI>>();
    pool.deposit_and_mint_p_token(
        &mut reserve, 
        sui, 
        test.sender(), 
        &clock, 
        test.ctx()
    );

    return_shared(pool);
    return_shared(reserve);
    return_shared(clock);
}

fun set_timestamp(test: &Scenario, timestamp_s: u64) {
    let mut clock = test.take_shared<Clock>();
    clock.set_for_testing(timestamp_s * 1000);
    return_shared(clock);
}