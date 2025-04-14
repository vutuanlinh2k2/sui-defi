module amm::pair;

use amm::constants;
use amm::decimal::{Self, Decimal, add, mul, div};
use amm::registry::Registry;
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance, Supply};
use sui::clock::{Self, Clock};
use sui::event;
use sui::vec_set::VecSet;
use sui::versioned::{Self, Versioned};

// === Errors ===
const EPackageVersionDisabled: u64 = 1;
const EInsufficientAmountToQuote: u64 = 2;
const EInsufficientLiquidity: u64 = 3;
const EMinimumAmountOfCoinsToProvideNotMet: u64 = 4;
const EMinimumAmountOfCoinsToWithdrawNotMet: u64 = 5;
const EInsufficientLPCoinAmountMinted: u64 = 6;
const EInsufficientLPCoinAmountBurned: u64 = 7;
const EInsufficientAmountIn: u64 = 8;
const EInsufficientAmountOut: u64 = 9;
const EInsufficientOutputAmount: u64 = 10;
const EInsufficientInputAmount: u64 = 11;
const EInsufficientProvidedAmount: u64 = 12;

// === Constants ===
const MINIMUM_LIQUIDITY: u64 = 10;

// === Structs ===
public struct Pair has key {
    id: UID,
    inner: Versioned,
}

public struct PairInner<phantom CoinA, phantom CoinB> has store {
    pair_id: ID,
    allowed_versions: VecSet<u64>,
    price_last_update_timestamp_s: u64,
    price_a_cumulative_last: Decimal, // need to scale up to present float, used for TWAP
    price_b_cumulative_last: Decimal, // need to scale up to present float, used for TWAP
    k_last: u128,
    coin_a_reserve: Balance<CoinA>,
    coin_b_reserve: Balance<CoinB>,
    fees: Balance<LPCoin<CoinA, CoinB>>, // fees collected by the protocol from trading
    lp_locked: Balance<LPCoin<CoinA, CoinB>>, // Locked LP Coins to ensure minimum liquidity
    lp_coin_supply: Supply<LPCoin<CoinA, CoinB>>,
}

/// Coins representing a user's share of a pair
public struct LPCoin<phantom CoinA, phantom CoinB> has drop {}

// === Events ===
public struct PairCreatedEvent has copy, drop {
    pair_id: ID,
    sender: address,
    coin_type_a: TypeName,
    coin_type_b: TypeName
}

public struct MintEvent has copy, drop {
    pair_id: ID,
    sender: address,
    amount_a: u64, // Provided amount of a
    amount_b: u64, // Provided amount of b
    amount_lp: u64, // Mint amount of lp
}

public struct BurnEvent has copy, drop {
    pair_id: ID,
    sender: address,
    amount_a: u64, // Withdraw amount of a
    amount_b: u64, // Withdraw amount of b
    amount_lp: u64, // Burn amount of lp
}

public struct SwapEvent has copy, drop {
    pair_id: ID,
    sender: address,
    amount_a_in: u64,
    amount_a_out: u64,
    amount_b_in: u64,
    amount_b_out: u64,
}

public struct UpdateEvent has copy, drop {
    amount_reserve_a: u64,
    amount_reserve_b: u64
}

// === Public View Functions ===
public fun allowed_versions<CoinA, CoinB>(self: &Pair): VecSet<u64> {
    let self = self.load_inner<CoinA, CoinB>();
    self.allowed_versions
}

public fun price_last_update_timestamp_s<CoinA, CoinB>(self: &Pair): u64 { // TODO: public(package) only
    let self = self.load_inner<CoinA, CoinB>();
    self.price_last_update_timestamp_s
}

public fun price_cumulative_last<CoinA, CoinB>(self: &Pair): (Decimal, Decimal) { // TODO: public(package) only
    let self = self.load_inner<CoinA, CoinB>();
    (self.price_a_cumulative_last, self.price_b_cumulative_last)
}

public fun k_last<CoinA, CoinB>(self: &Pair): u128 { // TODO: public(package) only
    let self = self.load_inner<CoinA, CoinB>();
    self.k_last
}

public fun reserves_amount<CoinA, CoinB>(self: &Pair): (u64, u64) {
    let self = self.load_inner<CoinA, CoinB>();
    (balance::value(&self.coin_a_reserve), balance::value(&self.coin_b_reserve))
}

public fun fees_amount<CoinA, CoinB>(self: &Pair): u64 {
    let self = self.load_inner<CoinA, CoinB>();
    balance::value(&self.fees)
}

public fun lp_locked_amount<CoinA, CoinB>(self: &Pair): u64 {
    let self = self.load_inner<CoinA, CoinB>();
    balance::value(&self.lp_locked)
}

public fun lp_coin_supply_amount<CoinA, CoinB>(self: &Pair): u64 {
    let self = self.load_inner<CoinA, CoinB>();
    balance::supply_value(&self.lp_coin_supply)
}

public(package) fun minimum_liquidity(): u64 {
    MINIMUM_LIQUIDITY
}

// === Package Mutative Functions ===

/// CoinA and CoinB should already in canonical order
public(package) fun create_pair_and_mint_lp_coin<CoinA, CoinB>(
    registry: &mut Registry,
    balance_a: Balance<CoinA>,
    balance_b: Balance<CoinB>,
    clock: &Clock,
    ctx: &mut TxContext,
): (Balance<LPCoin<CoinA, CoinB>>, ID) {
    let pair_id = object::new(ctx);

    let mut lp_coin_supply = balance::create_supply(LPCoin<CoinA, CoinB> {});

    let pair_inner = PairInner<CoinA, CoinB> {
        pair_id: pair_id.to_inner(),
        allowed_versions: registry.allowed_versions(),
        price_a_cumulative_last: decimal::from(0),
        price_b_cumulative_last: decimal::from(0),
        k_last: 0,
        price_last_update_timestamp_s: clock.timestamp_ms() / 1000,
        coin_a_reserve: balance::zero<CoinA>(),
        coin_b_reserve: balance::zero<CoinB>(),
        fees: balance::increase_supply(&mut lp_coin_supply, 0),
        lp_locked: balance::increase_supply(&mut lp_coin_supply, 0),
        lp_coin_supply: lp_coin_supply,
    };

    let mut pair = Pair {
        id: pair_id,
        inner: versioned::create(constants::current_version(), pair_inner, ctx),
    };

    let pair_id = object::id(&pair);
    registry.register_pair<CoinA, CoinB>(pair_id);

    event::emit(
        PairCreatedEvent {
            pair_id,
            sender: ctx.sender(),
            coin_type_a: type_name::get<CoinA>(),
            coin_type_b: type_name::get<CoinB>()
        }
    );

    let (balance_a_amount, balance_b_amount) = (
        balance::value(&balance_a),
        balance::value(&balance_b),
    );

    let (balance_lp, balance_a, balance_b) = add_liquidity_and_mint_lp_coin<CoinA, CoinB>(
        &mut pair,
        registry,
        balance_a,
        balance_b,
        balance_a_amount,
        balance_b_amount,
        clock,
        ctx,
    );

    transfer::share_object(pair);

    // When creating a pair, there is no remainder of the 2 coins
    balance::destroy_zero(balance_a);
    balance::destroy_zero(balance_b);

    (balance_lp, pair_id)
}

/// CoinA and CoinB should already in canonical order
public(package) fun add_liquidity_and_mint_lp_coin<CoinA, CoinB>(
    self: &mut Pair,
    registry: &Registry,
    mut balance_a: Balance<CoinA>,
    mut balance_b: Balance<CoinB>,
    amount_a_min: u64,
    amount_b_min: u64,
    clock: &Clock,
    ctx: &TxContext,
): (Balance<LPCoin<CoinA, CoinB>>, Balance<CoinA>, Balance<CoinB>) {
    let pair_id = object::id(self);
    let self = self.load_inner_mut<CoinA, CoinB>();
    let reserve_amount_a = balance::value(&self.coin_a_reserve);
    let reserve_amount_b = balance::value(&self.coin_b_reserve);

    let (amount_a, amount_b) = calculate_and_assert_amounts_to_provide(
        balance::value(&balance_a),
        balance::value(&balance_b),
        amount_a_min,
        amount_b_min,
        reserve_amount_a,
        reserve_amount_b,
    );
    let (amount_lp_mint, amount_lp_locked) = calculate_and_assert_lp_amount_to_mint_and_locked( 
        amount_a, 
        amount_b,
        reserve_amount_a,
        reserve_amount_b,
        balance::supply_value(&self.lp_coin_supply)
    );

    if (amount_lp_locked > 0) { // locked MINIMUM_LIQUIDITY when the pair is created
        balance::join(
            &mut self.lp_locked,
            balance::increase_supply(&mut self.lp_coin_supply, amount_lp_locked),
        );
    };

    let fees_on = registry.fees_on();
    self.mint_fees(fees_on);

    // split the initial Balance the user puts in and add them the to reserve
    // the remainders will still stay in the balances (can be 0)
    balance::join(&mut self.coin_a_reserve, balance::split(&mut balance_a, amount_a));
    balance::join(&mut self.coin_b_reserve, balance::split(&mut balance_b, amount_b));

    let balance_lp = balance::increase_supply(&mut self.lp_coin_supply, amount_lp_mint);

    update(self, clock);

    if (fees_on) {
        self.k_last = (balance::value(&self.coin_a_reserve) as u128) * (balance::value(&self.coin_b_reserve) as u128);
    };

    event::emit(
        MintEvent {
            pair_id,
            sender: ctx.sender(),
            amount_a,
            amount_b,
            amount_lp: amount_lp_mint
        }
    );

    (balance_lp, balance_a, balance_b)
}

public(package) fun remove_liquidity_and_burn_lp_coin<CoinA, CoinB>(
    self: &mut Pair,
    registry: &Registry,
    lp_balance: Balance<LPCoin<CoinA, CoinB>>,
    amount_a_min: u64,
    amount_b_min: u64,
    clock: &Clock,
    ctx: &TxContext
): (Balance<CoinA>, Balance<CoinB>) {
    let pair_id = object::id(self);
    let self = self.load_inner_mut<CoinA, CoinB>();
    let amount_lp= balance::value(&lp_balance);
    let reserve_amount_a = balance::value(&self.coin_a_reserve);
    let reserve_amount_b = balance::value(&self.coin_b_reserve);
    let lp_supply = balance::supply_value(&self.lp_coin_supply);

    let (withdraw_amount_a, withdraw_amount_b) = calculate_and_assert_amount_to_withdraw(
        amount_lp,
        reserve_amount_a,
        reserve_amount_b,
        amount_a_min,
        amount_b_min,
        lp_supply,
    );

    let fees_on = registry.fees_on();
    self.mint_fees(fees_on);

    balance::decrease_supply(&mut self.lp_coin_supply, lp_balance);

    let withdraw_balance_a = balance::split(&mut self.coin_a_reserve, withdraw_amount_a);
    let withdraw_balance_b = balance::split(&mut self.coin_b_reserve, withdraw_amount_b);

    update(self, clock);

    if (fees_on) {
        self.k_last = (balance::value(&self.coin_a_reserve) as u128) * (balance::value(&self.coin_b_reserve) as u128);
    };

    event::emit(
        BurnEvent {
            pair_id,
            sender: ctx.sender(),
            amount_a: withdraw_amount_a,
            amount_b: withdraw_amount_b,
            amount_lp
        }
    );

    (withdraw_balance_a, withdraw_balance_b)
}

public(package) fun swap_exact_coins_for_coins<CoinIn, CoinOut>(
    self: &mut Pair,
    balance_in: Balance<CoinIn>,
    min_amount_out: u64,
    is_coin_in_the_first_in_order: bool,
    ctx: &TxContext
): Balance<CoinOut> {
    let pair_id = object::id(self);

        let amount_in = balance::value(&balance_in);

    if (is_coin_in_the_first_in_order) {
        let self = self.load_inner_mut<CoinIn, CoinOut>();
        let amount_out = calculate_and_assert_amount_out(
            amount_in,
            min_amount_out, 
            balance::value(&self.coin_a_reserve), 
            balance::value(&self.coin_b_reserve)
        );
        balance::join(&mut self.coin_a_reserve, balance_in);
        let balance_out = balance::split(&mut self.coin_b_reserve, amount_out);

        event::emit(
            SwapEvent {
                pair_id,
                sender: ctx.sender(),
                amount_a_in: amount_in,
                amount_b_in: 0,
                amount_a_out: 0,
                amount_b_out: amount_out
            }
        );

        balance_out
    } else {
        let self = self.load_inner_mut<CoinOut, CoinIn>();
        let amount_out = calculate_and_assert_amount_out(
            amount_in,
            min_amount_out, 
            balance::value(&self.coin_b_reserve), 
            balance::value(&self.coin_a_reserve)
        );
        balance::join(&mut self.coin_b_reserve, balance_in);
        let balance_out = balance::split(&mut self.coin_a_reserve, amount_out);

        event::emit(
            SwapEvent {
                pair_id,
                sender: ctx.sender(),
                amount_a_in: 0,
                amount_b_in: amount_in,
                amount_a_out: amount_out,
                amount_b_out: 0
            }
        );

        balance_out
    }
}

public(package) fun swap_coins_for_exact_coins<CoinIn, CoinOut>(
    self: &mut Pair,
    mut balance_in: Balance<CoinIn>,
    amount_out: u64,
    is_coin_in_the_first_in_order: bool
): (Balance<CoinIn> , Balance<CoinOut>) {
    if (is_coin_in_the_first_in_order) {
        let self = self.load_inner_mut<CoinIn, CoinOut>();
        let amount_in = calculate_and_assert_amount_in(
            amount_out, 
            balance::value(&balance_in),
            balance::value(&self.coin_a_reserve), 
            balance::value(&self.coin_b_reserve)
        );
        balance::join(&mut self.coin_a_reserve, balance::split( &mut balance_in, amount_in));
        (balance_in, balance::split(&mut self.coin_b_reserve, amount_out))
    } else {
        let self = self.load_inner_mut<CoinOut, CoinIn>();
        let amount_in = calculate_and_assert_amount_in(
            amount_out, 
            balance::value(&balance_in),
            balance::value(&self.coin_b_reserve), 
            balance::value(&self.coin_a_reserve)
        );
        balance::join(&mut self.coin_b_reserve, balance::split(&mut balance_in, amount_in));
        (balance_in, balance::split(&mut self.coin_a_reserve, amount_out))
    }
}

public(package) fun fees_mut<CoinA, CoinB>(self: &mut Pair): &mut Balance<LPCoin<CoinA, CoinB>> {
    let self = self.load_inner_mut<CoinA, CoinB>();
    &mut self.fees
}

// === Private Functions ===

fun mint_fees<CoinA, CoinB>(
    self: &mut PairInner<CoinA, CoinB>,
    fees_on: bool
) {
    let k_last = self.k_last;

    if (fees_on) { 
        if (k_last != 0) {
            let amount_reserve_a = balance::value(&self.coin_a_reserve);
            let amount_reserve_b = balance::value(&self.coin_b_reserve);
            let root_k =
                (std::u128::sqrt((amount_reserve_a as u128) * (amount_reserve_b as u128))) as u64;
            let root_k_last = std::u128::sqrt(k_last) as u64;
            if (root_k > root_k_last) {
                let lp_coin_supply = balance::supply_value(&self.lp_coin_supply);
                let numerator = (lp_coin_supply as u128) * ((root_k - root_k_last) as u128);
                let denominator = (root_k as u128) * 5 + (root_k_last as u128);
                let fees_amount = (numerator / denominator) as u64;
                if (fees_amount > 0) {
                    balance::join(
                        &mut self.fees,
                        balance::increase_supply(&mut self.lp_coin_supply, fees_amount),
                    );
                }
            }
        }
    } else if (k_last != 0) {
        self.k_last = 0;
    }
}

/// Update price cumulative and last update timestamp
fun update<CoinA, CoinB>(self: &mut PairInner<CoinA, CoinB>, clock: &Clock) {
    let current_time_s = clock::timestamp_ms(clock) / 1000;
    let time_elapsed_s = current_time_s - self.price_last_update_timestamp_s;

    let amount_reserve_a = balance::value(&self.coin_a_reserve);
    let amount_reserve_b = balance::value(&self.coin_b_reserve);

    if (time_elapsed_s > 0 && amount_reserve_a > 0 && amount_reserve_b > 0) {
        self.price_a_cumulative_last = add(
            self.price_a_cumulative_last,
            div(
                mul(decimal::from(time_elapsed_s), decimal::from(amount_reserve_b)),
                decimal::from(amount_reserve_a)
            )
        );
        self.price_b_cumulative_last = add(
            self.price_b_cumulative_last,
            div(
                mul(decimal::from(time_elapsed_s), decimal::from(amount_reserve_a)),
                decimal::from(amount_reserve_b)
            )
        );
    };

    self.price_last_update_timestamp_s = current_time_s;

    event::emit(
        UpdateEvent {
            amount_reserve_a,
            amount_reserve_b,
        }
    );
}

// change to get reserve_amount 
fun calculate_and_assert_amounts_to_provide(
    amount_a: u64,
    amount_b: u64,
    amount_a_min: u64,
    amount_b_min: u64,
    reserve_a: u64,
    reserve_b: u64
): (u64, u64) {
    assert!(amount_a > 0 && amount_b > 0, EInsufficientProvidedAmount);
    if (reserve_a == 0 && reserve_b == 0) {
        (amount_a, amount_b)
    } else {
        let amount_b_optimal = quote_with_assert(amount_a, reserve_a, reserve_b);
        if (amount_b_optimal <= amount_b) {
            assert!(amount_b_optimal >= amount_b_min, EMinimumAmountOfCoinsToProvideNotMet);
            (amount_a, amount_b_optimal)
        } else {
            let amount_a_optimal = quote_with_assert(amount_b, reserve_b, reserve_a);
            assert!(amount_a_optimal <= amount_a);
            assert!(amount_a_optimal >= amount_a_min, EMinimumAmountOfCoinsToProvideNotMet);
            (amount_a_optimal, amount_b)
        }
    }
}

fun calculate_and_assert_lp_amount_to_mint_and_locked(
    amount_a: u64, 
    amount_b: u64, 
    reserve_a: u64,
    reserve_b: u64, 
    lp_supply: u64
): (u64, u64) {
    let (mint_amount, locked_amount) = if (lp_supply == 0) {
        let root = std::u128::sqrt((amount_a as u128) * (amount_b as u128)) as u64;
        assert!(root > MINIMUM_LIQUIDITY, EInsufficientProvidedAmount);
        (root - MINIMUM_LIQUIDITY, MINIMUM_LIQUIDITY)
    } else {
        (std::u64::min(
            (((amount_a as u128) * (lp_supply as u128)) / (reserve_a as u128)  as u64),
            (((amount_b as u128) * (lp_supply as u128)) / (reserve_b as u128)  as u64),
        ), 0)
    };
    assert!(mint_amount > 0, EInsufficientLPCoinAmountMinted);

    (mint_amount, locked_amount)
}

fun calculate_and_assert_amount_to_withdraw(
    amount_lp: u64, 
    reserve_a: u64, 
    reserve_b: u64, 
    amount_a_min: u64, 
    amount_b_min: u64,
    lp_supply: u64
): (u64, u64) {
    assert!(amount_lp > 0, EInsufficientLPCoinAmountBurned);
    let withdraw_amount_a = ((amount_lp as u128) * (reserve_a as u128) / (lp_supply as u128) as u64);
    let withdraw_amount_b = ((amount_lp as u128) * (reserve_b as u128) / (lp_supply as u128) as u64);

    assert!(withdraw_amount_a > 0 && withdraw_amount_b > 0, EInsufficientLPCoinAmountBurned);
    assert!(withdraw_amount_a >= amount_a_min && withdraw_amount_b >= amount_b_min, EMinimumAmountOfCoinsToWithdrawNotMet);
    assert!(withdraw_amount_a < reserve_a && withdraw_amount_b < reserve_b, EInsufficientLiquidity);

    (withdraw_amount_a, withdraw_amount_b)
}

fun calculate_and_assert_amount_out(
    amount_in: u64, 
    min_amount_out: u64, 
    amount_reserve_in: u64, 
    amount_reserve_out: u64
): u64 {
    assert!(amount_in > 0, EInsufficientAmountIn);
    assert!(amount_reserve_in > 0 && amount_reserve_out > 0, EInsufficientLiquidity);
    let amount_in_with_fee = (amount_in as u128) * 997;
    let numerator = amount_in_with_fee * (amount_reserve_out as u128);
    let denominator = (amount_reserve_in as u128) * 1000 + amount_in_with_fee;
    let amount_out = (numerator / denominator as u64);
    assert!(amount_out >= min_amount_out, EInsufficientAmountOut);
    amount_out
}

fun calculate_and_assert_amount_in(
    target_amount_out: u64,
    amount_balance_in: u64,
    amount_reserve_in: u64, 
    amount_reserve_out: u64
): u64 {
    assert!(target_amount_out > 0, EInsufficientOutputAmount);
    assert!(amount_reserve_in > 0 && amount_reserve_out > 0, EInsufficientLiquidity);
    let numerator = (amount_reserve_in as u128) * (target_amount_out as u128) * 1000;
    let denominator = ((amount_reserve_out - target_amount_out) as u128) * 997;
    let amount_in = 1 + ((numerator / denominator) as u64);
    assert!(amount_in <= amount_balance_in, EInsufficientInputAmount);
    amount_in
}

/// Given an amount of an asset and pair reserves,
/// returns an equivalent amount of the other asset.
fun quote_with_assert(amount_a: u64, amount_reserve_a: u64, amount_reserve_b: u64): u64 {
    assert!(amount_a > 0, EInsufficientAmountToQuote);
    assert!(amount_reserve_a > 0 && amount_reserve_b > 0, EInsufficientLiquidity);
    (((amount_a as u128) * (amount_reserve_b as u128)) / (amount_reserve_a as u128)  as u64)
}

public(package) fun load_inner<CoinA, CoinB>(self: &Pair): &PairInner<CoinA, CoinB> {
    let inner: &PairInner<CoinA, CoinB> = self.inner.load_value();
    let package_version = constants::current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionDisabled);

    inner
}

fun load_inner_mut<CoinA, CoinB>(self: &mut Pair): &mut PairInner<CoinA, CoinB> {
    let inner: &mut PairInner<CoinA, CoinB> = self.inner.load_value_mut();
    let package_version = constants::current_version();
    assert!(inner.allowed_versions.contains(&package_version), EPackageVersionDisabled);

    inner
}