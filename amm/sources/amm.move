module amm::amm;

use amm::pair::{Self, Pair};
use amm::registry::{Registry, AmmAdminCap};
use amm::utils::assert_identical_and_check_coins_order;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};

// === Errors ===
const EPairAlreadyExists: u64 = 1;
const EDeadlinePassed: u64 = 2;

// === Public Functions (Mutative) ===

public fun create_pair_and_mint_lp_token<CoinA, CoinB>(
    registry: &mut Registry,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    assert_deadline(deadline_timestamp_ms, clock);

    assert!(!registry.pair_exists<CoinA, CoinB>(), EPairAlreadyExists);

    let coins_in_order = assert_identical_and_check_coins_order<CoinA, CoinB>();

    let pair_id = if (coins_in_order) {
        create_pair_and_mint_lp_token_internal(registry, coin_a, coin_b, clock, ctx)
    } else {
        create_pair_and_mint_lp_token_internal(registry, coin_b, coin_a, clock, ctx)
    };

    pair_id
}

public fun add_liquidity_and_mint_lp_token<CoinA, CoinB>(
    registry: &Registry,
    pair: &mut Pair,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    amount_min_a: u64,
    amount_min_b: u64,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,  
) {
    assert_deadline(deadline_timestamp_ms, clock);

    let coins_in_order = assert_identical_and_check_coins_order<CoinA, CoinB>();

    if (coins_in_order) {
        add_liquidity_and_mint_lp_token_internal(
            registry,
            pair,
            coin_a,
            coin_b,
            amount_min_a,
            amount_min_b,
            clock,
            ctx,
        );
    } else {
        add_liquidity_and_mint_lp_token_internal(
            registry,
            pair,
            coin_b,
            coin_a,
            amount_min_b,
            amount_min_a,
            clock,
            ctx,
        );
    }
}

// === Public Functions (View) ===

public fun get_pair_id<CoinA, CoinB>(registry: &Registry): ID {
    registry.get_pair_id<CoinA, CoinB>()
}

// === Admin Functions ===
public fun remove_pair<CoinA, CoinB>(registry: &mut Registry, cap: &AmmAdminCap) {
    registry.unregister_pair<CoinA, CoinB>(cap);
}

public fun set_fees_claimer(
    registry: &mut Registry,
    fees_claimer: address,
    _cap: &AmmAdminCap,
) {
    registry.set_fees_claimer(fees_claimer, _cap);
}

public fun remove_fees_claimer(registry: &mut Registry, _cap: &AmmAdminCap) {
    registry.remove_fees_claimer(_cap);
}

public fun claim_fees<CoinA, CoinB>(
    registry: &mut Registry,
    pair: &mut Pair,
    _cap: &AmmAdminCap,
    ctx: &mut TxContext,
) {
    let fees_balance = pair.fees_mut<CoinA, CoinB>();
    transfer::public_transfer(
        coin::from_balance(balance::withdraw_all(fees_balance), ctx),
        option::extract(&mut registry.fees_claimer()),
    );
}

// === Private Functions ===
fun create_pair_and_mint_lp_token_internal<CoinA, CoinB>(
    registry: &mut Registry,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let (balance_lp, pair_id) = pair::create_pair_and_mint_lp_token(
        registry,
        coin::into_balance(coin_a),
        coin::into_balance(coin_b),
        clock,
        ctx,
    );

    send_coin_if_not_zero(balance_lp, ctx.sender(), ctx);

    pair_id
}

fun add_liquidity_and_mint_lp_token_internal<CoinA, CoinB>(
    registry: &Registry,
    pair: &mut Pair,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    amount_min_a: u64,
    amount_min_b: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let balance_a = coin::into_balance(coin_a);
    let balance_b = coin::into_balance(coin_b);

    let (balance_lp, balance_a, balance_b) = pair::add_liquidity_and_mint_lp_token(
        registry,
        pair,
        balance_a,
        balance_b,
        amount_min_a,
        amount_min_b,
        clock,
    );

    send_coin_if_not_zero(balance_lp, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_a, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_b, ctx.sender(), ctx);
}

fun assert_deadline(deadline_timestamp_ms: u64, clock: &Clock) {
    assert!(deadline_timestamp_ms < clock.timestamp_ms(), EDeadlinePassed);
}

fun send_coin_if_not_zero<CoinType>(
    balance: Balance<CoinType>,
    recipient: address,
    ctx: &mut TxContext,
) {
    if (balance::value(&balance) > 0) {
        transfer::public_transfer(coin::from_balance(balance, ctx), recipient);
    } else {
        balance::destroy_zero(balance);
    }
}
