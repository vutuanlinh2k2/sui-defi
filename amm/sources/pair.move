module amm::pair;

use sui::balance::{Self, Balance, Supply};
use sui::clock::Clock;
use sui::dynamic_field;

// === Errors ===

// === Structs ===
public struct Pair<phantom P> has key, store {
    id: UID,
    amm_id: ID,
    price_last_update_timestamp_s: u64,
    priceACumulativeLast: u128,
    priceBCumulativeLast: u128,
    k_last: u128,
}

/// Balances are stored in a dynamic field to avoid typing the Pair with CoinType
public struct Balances<phantom P, phantom CoinA, phantom CoinB> has store {
    lp_token_supply: Supply<LPToken<P, CoinA, CoinB>>,
    coinA_balance: Balance<CoinA>,
    coinB_balance: Balance<CoinB>,
}

/// Tokens representing a user's share of a pair
public struct LPToken<phantom P, phantom CoinA, phantom B> has drop {}

public struct BalancesKey has copy, drop, store {}

// === Package Functions ===

public(package) fun create_pair<P, CoinA, CoinB>(
    amm_id: ID,
    clock: &Clock,
    ctx: &mut TxContext,
): Pair<P> {
    let mut pair = Pair<P> {
        id: object::new(ctx),
        amm_id,
        priceACumulativeLast: 0,
        priceBCumulativeLast: 0,
        k_last: 0,
        price_last_update_timestamp_s: clock.timestamp_ms() / 1000,
    };

    dynamic_field::add(
        &mut pair.id,
        BalancesKey {},
        Balances<P, CoinA, CoinB> {
            lp_token_supply: balance::create_supply(LPToken<P, CoinA, CoinB> {}),
            coinA_balance: balance::zero<CoinA>(),
            coinB_balance: balance::zero<CoinB>(),
        },
    );

    pair
}
