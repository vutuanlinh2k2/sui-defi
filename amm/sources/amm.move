module amm::amm;

use amm::pair::{Self, Pair, LPCoin};
use amm::registry::{Registry, AmmAdminCap};
use amm::utils::{assert_identical_and_check_coins_order};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};

// === Errors ===
const EDeadlinePassed: u64 = 1;

// === Public Mutative Functions ===

public fun create_pair_and_mint_lp_coin<CoinA, CoinB>(
    registry: &mut Registry,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    assert_deadline(deadline_timestamp_ms, clock);

    let coins_in_order = assert_identical_and_check_coins_order<CoinA, CoinB>();

    let pair_id = if (coins_in_order) {
        create_pair_and_mint_lp_coin_internal(registry, coin_a, coin_b, clock, ctx)
    } else {
        create_pair_and_mint_lp_coin_internal(registry, coin_b, coin_a, clock, ctx)
    };

    pair_id
}

public fun add_liquidity_and_mint_lp_coin<CoinA, CoinB>(
    registry: &Registry,
    pair: &mut Pair,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    amount_a_min: u64,
    amount_b_min: u64,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,  
) {  
    assert_deadline(deadline_timestamp_ms, clock);

    let coins_in_order = assert_identical_and_check_coins_order<CoinA, CoinB>();

    if (coins_in_order) {
        add_liquidity_and_mint_lp_coin_internal(
            registry,
            pair,
            coin_a,
            coin_b,
            amount_a_min,
            amount_b_min,
            clock,
            ctx,
        );
    } else {
        add_liquidity_and_mint_lp_coin_internal(
            registry,
            pair,
            coin_b,
            coin_a,
            amount_b_min,
            amount_a_min,
            clock,
            ctx,
        );
    }
}

/// If the coins are not in canonical order, this will raise error
public fun remove_liquidity_and_burn_lp_coin<CoinA, CoinB>(
    registry: &Registry,
    pair: &mut Pair,
    coin_lp: Coin<LPCoin<CoinA, CoinB>>,
    amount_a_min: u64,
    amount_b_min: u64,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_deadline(deadline_timestamp_ms, clock);

    let (balance_a, balance_b) = pair.remove_liquidity_and_burn_lp_coin<CoinA, CoinB>(
        registry, 
        coin::into_balance(coin_lp), 
        amount_a_min, 
        amount_b_min, 
        clock,
        ctx)
    ;

    send_coin_if_not_zero(balance_a, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_b, ctx.sender(), ctx);
}

public fun swap_exact_coins_for_coins<CoinIn, CoinOut>(
    pair: &mut Pair,
    coin_in: Coin<CoinIn>,
    min_amount_out: u64,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert_deadline(deadline_timestamp_ms, clock);

    let is_coin_in_the_first_in_order = assert_identical_and_check_coins_order<CoinIn, CoinOut>();
    
    let balance_out = pair.swap_exact_coins_for_coins<CoinIn, CoinOut>( coin::into_balance(coin_in), min_amount_out, is_coin_in_the_first_in_order, ctx);

    send_coin_if_not_zero(balance_out, ctx.sender(), ctx);
}

public fun swap_coins_for_exact_coins<CoinIn, CoinOut>(
    pair: &mut Pair,
    coin_in: Coin<CoinIn>,
    amount_out: u64,
    deadline_timestamp_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert_deadline(deadline_timestamp_ms, clock);

    let is_coin_in_the_first_in_order = assert_identical_and_check_coins_order<CoinIn, CoinOut>();

    let (balance_remainder, balance_out) = pair.swap_coins_for_exact_coins<CoinIn, CoinOut>( 
        coin::into_balance(coin_in), 
        amount_out, 
        is_coin_in_the_first_in_order
    );

    send_coin_if_not_zero(balance_remainder, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_out, ctx.sender(), ctx);
}

// === Public View Functions ===

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
fun create_pair_and_mint_lp_coin_internal<CoinA, CoinB>(
    registry: &mut Registry,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let (balance_lp, pair_id) = pair::create_pair_and_mint_lp_coin(
        registry,
        coin::into_balance(coin_a),
        coin::into_balance(coin_b),
        clock,
        ctx,
    );

    send_coin_if_not_zero(balance_lp, ctx.sender(), ctx);

    pair_id
}

fun add_liquidity_and_mint_lp_coin_internal<CoinA, CoinB>(
    registry: &Registry,
    pair: &mut Pair,
    coin_a: Coin<CoinA>,
    coin_b: Coin<CoinB>,
    amount_a_min: u64,
    amount_b_min: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let balance_a = coin::into_balance(coin_a);
    let balance_b = coin::into_balance(coin_b);

    let (balance_lp, balance_a, balance_b) = pair.add_liquidity_and_mint_lp_coin(
        registry,
        balance_a,
        balance_b,
        amount_a_min,
        amount_b_min,
        clock,
        ctx
    );

    send_coin_if_not_zero(balance_lp, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_a, ctx.sender(), ctx);
    send_coin_if_not_zero(balance_b, ctx.sender(), ctx);
}

fun assert_deadline(deadline_timestamp_ms: u64, clock: &Clock) {
    assert!(deadline_timestamp_ms >= clock.timestamp_ms(), EDeadlinePassed);
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