#[test_only]
module prize_savings::yield_simulator_tests;

use prize_savings::yield_simulator::{Self, YSRegistry, YSReserve, YBToken};
use prize_savings::test_utils::{deposit_coin_to_address};
use sui::coin::{Coin};
use sui::test_scenario::{begin, end, return_shared, return_to_sender};
use sui::{test_utils as system_test_utils};

const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

public struct SUI has store {}

#[test]
public fun test_yield_simulator() {
    let mut test = begin(OWNER);

    test.next_tx(OWNER);
    let registry_id = {
        yield_simulator::test_yield_simulator_registry(test.ctx())
    };

    test.next_tx(OWNER);
    let reserve_id = {
        let mut registry = test.take_shared_by_id<YSRegistry>(registry_id);
        let admin_cap = yield_simulator::get_yield_simulator_admin_cap_for_testing(test.ctx());
        let reserve_id = yield_simulator::create_reserve<SUI>(&mut registry, &admin_cap, test.ctx());

        return_shared(registry);
        system_test_utils::destroy(admin_cap);

        reserve_id
    };

    test.next_tx(ALICE);
    {
        deposit_coin_to_address<SUI>(1_000_000_000, ALICE, &mut test);
        deposit_coin_to_address<SUI>(500_000_000, OWNER, &mut test);
    };

    test.next_tx(ALICE);
    {
        let mut reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        let sui = test.take_from_sender<Coin<SUI>>();
        reserve.deposit_and_mint_yb_token(sui, test.ctx());

        return_shared(reserve);
    };

    test.next_tx(ALICE);
    {
        let reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        assert!(reserve.token_balance_amount() == 1_000_000_000);
        assert!(reserve.yb_token_supply_amount() == 1_000_000_000);
        return_shared(reserve);
    };

    test.next_tx(OWNER);
    {
        let mut reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        let sui = test.take_from_sender<Coin<SUI>>();
        reserve.increase_reserve_balance(sui);
        return_shared(reserve);
    };

    test.next_tx(ALICE);
    {
        let reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        assert!(reserve.token_balance_amount() == 1_500_000_000);
        assert!(reserve.yb_token_supply_amount() == 1_000_000_000);
        return_shared(reserve);
    };

    test.next_tx(ALICE);
    {
        let mut reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        let yb_tokens = test.take_from_sender<Coin<YBToken<SUI>>>();
        reserve.redeem_yb_token_and_withdraw(yb_tokens, test.ctx());
        return_shared(reserve);
    };

    test.next_tx(ALICE);
    {
        let reserve = test.take_shared_by_id<YSReserve<SUI>>(reserve_id);
        let sui = test.take_from_sender<Coin<SUI>>();
        assert!(&sui.value() == 1_500_000_000);
        assert!(reserve.yb_token_supply_amount() == 0);
        assert!(reserve.token_balance_amount() == 0);

        test.return_to_sender(sui);
        return_shared(reserve);
    };

    test.end();
}

// deposit 

// add more liquidity

// withdraw