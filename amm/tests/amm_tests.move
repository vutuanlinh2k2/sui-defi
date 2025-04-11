#[test_only]
module amm::amm_tests;

use amm::amm;
use amm::constants::{current_version};
use amm::decimal::{Self, eq};
use amm::pair::{Pair, LPCoin, minimum_liquidity};
use amm::registry::{Self, Registry};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::test_scenario::{Scenario, begin, end, return_shared};

const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

public struct FSUI has store {}
public struct USDT has store {}

/* 
Plan all the tests 

create pair (use this inside in others too)
- create function for this
- fail
    - Cases 1 ...
    - Cases 2 ... 

add liquidity 
- create function for this (after create pair)
- fail cases

remove liquidity 
- create function for this (after create pair)
- fail cases

swap exact coins for coins
- fail cases

swap coins for exact coins
- fail cases

UTILITIES
- create registry
- create new tokens
 */

#[test]
fun create_pair_successfully () {
    let mut test = begin(OWNER);
    let registry_id = setup_test(OWNER, &mut test);

    test.next_tx(OWNER);
    {
        deposit_coin_to_address<FSUI>(10_000_000_000, ALICE, &mut test);
        deposit_coin_to_address<USDT>(40_000_000_000, ALICE, &mut test);
    };

    test.next_tx(ALICE);
    let pair_id = {
        let clock = test.take_shared<Clock>();
        let mut registry = test.take_shared_by_id<Registry>(registry_id);
    
        let id = create_pair<FSUI, USDT>(
            &mut registry,
            test.take_from_sender<Coin<FSUI>>(),
            test.take_from_sender<Coin<USDT>>(),
            clock.timestamp_ms(),
            &clock,
            &mut test
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
        assert!(pair.k_last<FSUI, USDT>() == 10_000_000_000 * 40_000_000_000);
        let (reserve_a_amount, reserve_b_amount) = pair.reserves_amount<FSUI, USDT>();
        assert!(reserve_a_amount == 10_000_000_000);
        assert!(reserve_b_amount == 40_000_000_000);
        assert!(pair.fees_amount<FSUI, USDT>() == 0);
        assert!(pair.lp_locked_amount<FSUI, USDT>() == minimum_liquidity());
        assert!(pair.lp_coin_supply_amount<FSUI, USDT>() == 20_000_000_000);

        return_shared(pair);
    };

    test.end();
}

#[test_only]
fun create_pair<CoinA, CoinB> (
    registry: &mut Registry,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    test: &mut Scenario
): ID {
    amm::create_pair_and_mint_lp_coin<CoinA, CoinB> (
        registry,
        coin_a,
        coin_b,
        deadline_timestamp_ms,
        clock,
        test.ctx()
    )
}

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