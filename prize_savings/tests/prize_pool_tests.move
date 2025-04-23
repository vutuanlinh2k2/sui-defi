module prize_savings::prize_pool_tests;

use prize_savings::prize_pool::{Self, PrizePool, create_test_prize_pool};
use prize_savings::test_utils::{set_timestamp_s};
use sui::clock::{Self, Clock};
use sui::coin::{Coin};
use sui::test_scenario::{begin, end, return_shared};
use std::debug::{print};

const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

public struct SUI has store {}

#[test]
public fun test_prize_pool() {
    let mut test = begin(OWNER);
    {
        clock::create_for_testing(test.ctx()).share_for_testing();
        create_test_prize_pool<SUI>(test.ctx());
    };

    test.next_tx(ALICE);
    {
        let prize_pool = test.take_shared<PrizePool<SUI>>();
        let mut i = 0;

        // Tier 2
        while (i < 16) {
            let is_winner = prize_pool.is_winner(ALICE,2, i);
            print(&is_winner);

            i = i + 1;
        };

        // Tier 1
        let mut i = 0;
        while (i < 4) {
            let is_winner = prize_pool.is_winner(ALICE, 1, i);
            print(&is_winner);

            i = i + 1;
        };

        // Tier 0 (Grand Prize)
        let is_winner = prize_pool.is_winner(ALICE, 0, 0);
        print(&is_winner);

        return_shared(prize_pool);
    };

    test.next_tx(ALICE);
    {
        let mut prize_pool = test.take_shared<PrizePool<SUI>>();
        let clock = test.take_shared<Clock>();
        prize_pool.claim_prize(ALICE, 2, 0, &clock, test.ctx()); // win

        return_shared(prize_pool);
        return_shared(clock);
    };

    test.next_tx(ALICE);
    {
        let sui = test.take_from_sender<Coin<SUI>>();
        assert!(sui.value() == 12_500_000);

        test.return_to_sender(sui);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = prize_pool::EDeadlinePassed)]
fun test_prize_pool_failed_deadline_passed() {
    let mut test = begin(OWNER);

    {
        clock::create_for_testing(test.ctx()).share_for_testing();
        create_test_prize_pool<SUI>(test.ctx());
    };

    test.next_tx(ALICE);
    set_timestamp_s(&test, 86_400 * 2 + 1);

    test.next_tx(ALICE);
    {
        let mut prize_pool = test.take_shared<PrizePool<SUI>>();
        let clock = test.take_shared<Clock>();
        prize_pool.claim_prize(ALICE, 2, 0, &clock, test.ctx());

        return_shared(prize_pool);
        return_shared(clock);
    };

    test.end();
}

#[test]
#[expected_failure(abort_code = prize_pool::EAlreadyClaimed)]
fun test_prize_pool_failed_already_claimed() {
    let mut test = begin(OWNER);
    
    {
        clock::create_for_testing(test.ctx()).share_for_testing();
        create_test_prize_pool<SUI>(test.ctx());
    };

    test.next_tx(ALICE);
    {
        let mut prize_pool = test.take_shared<PrizePool<SUI>>();
        let clock = test.take_shared<Clock>();
        prize_pool.claim_prize(ALICE, 2, 0, &clock, test.ctx());

        return_shared(prize_pool);
        return_shared(clock);
    };

    test.next_tx(ALICE);
    {
        let mut prize_pool = test.take_shared<PrizePool<SUI>>();
        let clock = test.take_shared<Clock>();
        prize_pool.claim_prize(ALICE, 2, 0, &clock, test.ctx());

        return_shared(prize_pool);
        return_shared(clock);
    };

    test.end();
}
