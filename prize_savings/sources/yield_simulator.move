/// A module that simulate a protocol that earn yields for depositors
module prize_savings::yield_simulator;

use prize_savings::decimal::{Self, Decimal, div, mul, floor};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::versioned::{Self, Versioned};
use sui::table::{Self, Table};
use std::type_name::{Self, TypeName};

// === Errors ===
const EInvalidVersion: u64 = 1;
const EReserveAlreadyExists: u64 = 2;
const EReserveNotExists: u64 = 3;

// === Constants ===
const YIELD_SIMULATOR_VERSION: u64 = 1;

// === Structs ===

public struct YS_REGISTRY has drop {}

public struct YSRegistry has key {
    id: UID,
    inner: Versioned,
}

public struct YSRegistryInner has store {
    current_version: u64,
    reserves: Table<ReserveKey, ID>,
}

public struct YSAdminCap has key, store {
    id: UID,
}

public struct ReserveKey has copy, drop, store {
    asset: TypeName
}

public struct YSReserve<phantom T> has key {
    id: UID,
    token_balance: Balance<T>,
    yb_token_supply: Supply<YBToken<T>>
}

public struct YBToken<phantom T> has drop {}

// === Public View Functions ===
public fun token_balance_amount<T>(reserve: &YSReserve<T>): u64 {
    balance::value(&reserve.token_balance)
}

public fun yb_token_supply_amount<T>(reserve: &YSReserve<T>): u64 {
    balance::supply_value(&reserve.yb_token_supply)
}

// === Public Mutative Functions ===

#[allow(lint(self_transfer))]
public fun deposit_and_mint_yb_token<T>(
    reserve: &mut YSReserve<T>, 
    liquidity: Coin<T>, 
    ctx: &mut TxContext
) {
    assert!(coin::value(&liquidity) > 0);

    let yb_token_ratio = reserve.get_yb_token_ratio();

    let new_yb_token_amount = floor(div(
        decimal::from(coin::value(&liquidity)),
        yb_token_ratio
    ));

    balance::join(&mut reserve.token_balance, coin::into_balance(liquidity));
    let yb_tokens = coin::from_balance(balance::increase_supply(&mut reserve.yb_token_supply, new_yb_token_amount), ctx);
    transfer::public_transfer(yb_tokens, ctx.sender());
}

#[allow(lint(self_transfer))]
public fun redeem_yb_token_and_withdraw<T>(
    reserve: &mut YSReserve<T>, 
    yb_tokens: Coin<YBToken<T>>, 
    ctx: &mut TxContext
) {
    assert!(coin::value(&yb_tokens) > 0);
    let yb_token_ratio = reserve.get_yb_token_ratio();
    let liquidity_amount = floor(mul(
        decimal::from(coin::value(&yb_tokens)),
        yb_token_ratio
    ));

    balance::decrease_supply(&mut reserve.yb_token_supply, coin::into_balance(yb_tokens));
    let tokens = coin::from_balance(balance::split(&mut reserve.token_balance, liquidity_amount), ctx);
    transfer::public_transfer(tokens, ctx.sender());
}

/// Manually deposit more into the balance so when the amount when withdrawing
/// will be bigger than when depositing
public fun increase_reserve_balance<T>(reserve: &mut YSReserve<T>, tokens: Coin<T>) {
    assert!(coin::value(&tokens) > 0);
    balance::join(&mut reserve.token_balance, coin::into_balance(tokens));
}

// === Admin Functions ===

public fun create_yield_simulator(ctx: &mut TxContext): (ID, YSAdminCap)  {
    let registry_inner = YSRegistryInner {
        current_version: YIELD_SIMULATOR_VERSION,
        reserves: table::new(ctx),
    };
    let registry = YSRegistry {
        id: object::new(ctx),
        inner: versioned::create(
            YIELD_SIMULATOR_VERSION,
            registry_inner,
            ctx,
        ),
    };
    let id = object::id(&registry);

    transfer::share_object(registry);

    let admin_cap = YSAdminCap { id: object::new(ctx) };

    (id, admin_cap)
}

public fun create_reserve<T>(registry: &mut YSRegistry, cap: &YSAdminCap, ctx: &mut TxContext): ID {
    let reserve = YSReserve<T> {
        id: object::new(ctx),
        token_balance: balance::zero<T>(),
        yb_token_supply: balance::create_supply(YBToken<T> {})
    };

    let reserve_id = object::id(&reserve);

    register_reserve<T>(registry, reserve_id, cap);

    transfer::share_object(reserve);

    reserve_id
}

public fun remove_reserve<T>(registry: &mut YSRegistry) {
    let registry = registry.load_inner_mut();
    let key = ReserveKey {
        asset: type_name::get<T>()
    };
    assert!(registry.reserves.contains(key), EReserveNotExists);
    registry.reserves.remove<ReserveKey, ID>(key);
}

// === Private Functions ===

fun register_reserve<T>(registry: &mut YSRegistry, reserve_id: ID, _cap: &YSAdminCap) {
    let registry = registry.load_inner_mut();
    let key = ReserveKey {
        asset: type_name::get<T>()
    };
    assert!(!registry.reserves.contains(key), EReserveAlreadyExists);
    registry.reserves.add(key, reserve_id);
}

fun get_yb_token_ratio<T>(reserve: &YSReserve<T>): Decimal {
    let yb_token_supply_amount = balance::supply_value(&reserve.yb_token_supply);
    if (yb_token_supply_amount == 0) {
        decimal::from(1)
    } else {
        let total_balance = balance::value(&reserve.token_balance);
        div(
            decimal::from(total_balance),
            decimal::from(yb_token_supply_amount)
        )
    }
}

fun load_inner_mut(self: &mut YSRegistry): &mut YSRegistryInner {
    let inner: &mut YSRegistryInner = self.inner.load_value_mut();
    assert!(inner.current_version == YIELD_SIMULATOR_VERSION, EInvalidVersion);

    inner
}

// === Test Functions ===

#[test_only]
public fun test_yield_simulator_registry(ctx: &mut TxContext): ID {
    let registry_inner = YSRegistryInner {
        current_version: YIELD_SIMULATOR_VERSION,
        reserves: table::new(ctx),
    };

    let registry = YSRegistry {
        id: object::new(ctx),
        inner: versioned::create(
            YIELD_SIMULATOR_VERSION,
            registry_inner,
            ctx,
        ),
    };

    let id = object::id(&registry);
    transfer::share_object(registry);

    id
}

#[test_only]
public fun get_yield_simulator_admin_cap_for_testing(ctx: &mut TxContext): YSAdminCap {
    YSAdminCap { id: object::new(ctx) }
}