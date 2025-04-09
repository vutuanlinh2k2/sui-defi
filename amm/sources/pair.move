module amm::pair;

use amm::constants;
use amm::registry::Registry;
use sui::balance::{Self, Balance, Supply};
use sui::clock::{Self, Clock};
use sui::vec_set::VecSet;
use sui::versioned::{Self, Versioned};

const MINIMUM_LIQUIDITY: u64 = 10; // Set the same as Cetus

// === Errors ===
const EPackageVersionDisabled: u64 = 1;
const EInsufficientAmount: u64 = 2;
const EInsufficientLiquidity: u64 = 3;
const EInsufficientAmountOfCoinB: u64 = 4;
const EInsufficientAmountOfCoinA: u64 = 5;
const EInsufficientAmountOfCoins: u64 = 6;
const EInsufficientLPCoinMinted: u64 = 7;
const EInsufficientLPCoinBurned: u64 = 8;
const EInsufficientWithdrawAmount: u64 = 9;
const EInsufficientAmountIn: u64 = 10;
const EInsufficientAmountOut: u64 = 11;
const EInsufficientOutputAmount: u64 = 12;
const EInsufficientInputAmount: u64 = 13;

// === Structs ===
public struct Pair has key {
    id: UID,
    inner: Versioned,
}

public struct PairInner<phantom CoinA, phantom CoinB> has store {
    pair_id: ID,
    allowed_versions: VecSet<u64>,
    price_last_update_timestamp_s: u64,
    price_a_cumulative_last: u128,
    price_b_cumulative_last: u128,
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
// TODO: add new events + fields
public struct MintEvent {}
public struct BurnEvent {}
public struct SwapEvent {}
public struct UpdateEvent {}

// === Admin Functions ===

// === Package Functions ===

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
        price_a_cumulative_last: 0,
        price_b_cumulative_last: 0,
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

    let (balance_a_value, balance_b_value) = (
        balance::value(&balance_a),
        balance::value(&balance_b),
    );

    let (balance_lp, balance_a, balance_b) = add_liquidity_and_mint_lp_coin<CoinA, CoinB>(
        &mut pair,
        registry,
        balance_a,
        balance_b,
        balance_a_value,
        balance_b_value,
        clock,
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
): (Balance<LPCoin<CoinA, CoinB>>, Balance<CoinA>, Balance<CoinB>) {
    let (amount_a, amount_b) = calculate_coin_amounts_to_provide<CoinA, CoinB>(
        self,
        balance::value(&balance_a),
        balance::value(&balance_b),
        amount_a_min,
        amount_b_min,
    );
    let amount_lp_mint = calculate_lp_amount_to_mint<CoinA, CoinB>(self, amount_a, amount_b);

    let self = self.load_inner_mut();
    let fees_on = check_fees_on_and_mint(registry, self);

    // split the initial Balance the user puts in and add them the to reserve
    // the remainders will still stay in the balances (can be 0)
    balance::join(&mut self.coin_a_reserve, balance::split(&mut balance_a, amount_a));
    balance::join(&mut self.coin_b_reserve, balance::split(&mut balance_b, amount_b));

    let balance_lp = balance::increase_supply(&mut self.lp_coin_supply, amount_lp_mint);

    update(self, clock);

    if (fees_on) {
        self.k_last = (balance::value(&self.coin_a_reserve) as u128) * (balance::value(&self.coin_b_reserve) as u128);
    };

    (balance_lp, balance_a, balance_b)
}

public(package) fun remove_liquidity_and_burn_lp_coin<CoinA, CoinB>(
    self: &mut Pair,
    registry: &Registry,
    lp_balance: Balance<LPCoin<CoinA, CoinB>>,
    amount_a_min: u64,
    amount_b_min: u64,
    clock: &Clock
): (Balance<CoinA>, Balance<CoinB>) {
    let (withdraw_amount_a, withdraw_amount_b) = calculate_amount_to_withdraw<CoinA, CoinB>(
        self,
        balance::value(&lp_balance),
    );

    assert!(withdraw_amount_a >= amount_a_min && withdraw_amount_b >= amount_b_min, EInsufficientWithdrawAmount);

    let self = self.load_inner_mut<CoinA, CoinB>();
    let fees_on = check_fees_on_and_mint(registry, self);

    balance::decrease_supply(&mut self.lp_coin_supply, lp_balance);

    let withdraw_balance_a = balance::split(&mut self.coin_a_reserve, withdraw_amount_a);
    let withdraw_balance_b = balance::split(&mut self.coin_b_reserve, withdraw_amount_b);

    update(self, clock);

    if (fees_on) {
        self.k_last = (balance::value(&self.coin_a_reserve) as u128) * (balance::value(&self.coin_b_reserve) as u128);
    };

    (withdraw_balance_a, withdraw_balance_b)
}

public(package) fun swap_exact_coins_for_coins<CoinIn, CoinOut>(
    self: &mut Pair,
    balance_in: Balance<CoinIn>,
    min_amount_out: u64,
    is_coin_in_the_first_in_order: bool
): Balance<CoinOut> {

    if (is_coin_in_the_first_in_order) {
        let self = self.load_inner_mut<CoinIn, CoinOut>();
        let amount_out = calculate_amount_out(balance::value(&balance_in), balance::value(&self.coin_a_reserve), balance::value(&self.coin_b_reserve));
        assert!(amount_out >= min_amount_out, EInsufficientAmountOut);
        balance::join(&mut self.coin_a_reserve, balance_in);
        balance::split(&mut self.coin_b_reserve, amount_out)
    } else {
        let self = self.load_inner_mut<CoinOut, CoinIn>();
        let amount_out = calculate_amount_out(balance::value(&balance_in), balance::value(&self.coin_a_reserve), balance::value(&self.coin_b_reserve));
        assert!(amount_out >= min_amount_out, EInsufficientAmountOut);
        balance::join(&mut self.coin_b_reserve, balance_in);
        balance::split(&mut self.coin_a_reserve, amount_out)
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
        let amount_in = calculate_amount_in(amount_out, balance::value(&self.coin_a_reserve), balance::value(&self.coin_b_reserve));
        assert!(amount_in <= balance::value(&balance_in), EInsufficientInputAmount);
        balance::join(&mut self.coin_a_reserve, balance::split( &mut balance_in, amount_in));
        (balance_in, balance::split(&mut self.coin_b_reserve, amount_out))
    } else {
        let self = self.load_inner_mut<CoinOut, CoinIn>();
        let amount_in = calculate_amount_in(amount_out, balance::value(&self.coin_a_reserve), balance::value(&self.coin_b_reserve));
        assert!(amount_in <= balance::value(&balance_in), EInsufficientInputAmount);
        balance::join(&mut self.coin_b_reserve, balance::split(&mut balance_in, amount_in));
        (balance_in, balance::split(&mut self.coin_a_reserve, amount_out))
    }
}

// Change this function to return a mutable reference
public(package) fun fees_mut<CoinA, CoinB>(self: &mut Pair): &mut Balance<LPCoin<CoinA, CoinB>> {
    let self = self.load_inner_mut<CoinA, CoinB>();
    &mut self.fees
}

// === Private Functions ===

fun check_fees_on_and_mint<CoinA, CoinB>(
    registry: &Registry,
    self: &mut PairInner<CoinA, CoinB>,
): bool {
    let fees_on = option::is_some(&registry.fees_claimer());
    let k_last = self.k_last;

    if (fees_on) { if (k_last != 0) {
            let amount_reserve_a = balance::value(&self.coin_a_reserve);
            let amount_reserve_b = balance::value(&self.coin_b_reserve);
            let lp_coin_supply = balance::supply_value(&self.lp_coin_supply);
            let root_k =
                (std::u128::sqrt((amount_reserve_a as u128) * (amount_reserve_b as u128))) as u64;
            let root_k_last = std::u128::sqrt(k_last) as u64;
            if (root_k > root_k_last) {
                let numerator = (lp_coin_supply as u128) * ((root_k - root_k_last) as u128);
                let denominator = (root_k as u128) * 5 + (root_k_last as u128);
                let liquidity = (numerator / denominator) as u64;
                if (liquidity > 0) {
                    balance::join(
                        &mut self.fees,
                        balance::increase_supply(&mut self.lp_coin_supply, liquidity),
                    );
                }
            }
        } else {
            self.k_last = 0;
        } };

    fees_on
}

/// Update price cumulative, and price_last_update_timestamp_s
fun update<CoinA, CoinB>(self: &mut PairInner<CoinA, CoinB>, clock: &Clock) {
    let current_time_s = clock::timestamp_ms(clock) / 1000;
    let time_elapsed_s = current_time_s - self.price_last_update_timestamp_s;

    let amount_reserve_a = balance::value(&self.coin_a_reserve);
    let amount_reserve_b = balance::value(&self.coin_b_reserve);

    if (time_elapsed_s > 0) {
        self.price_a_cumulative_last =
            self.price_a_cumulative_last + (amount_reserve_b / amount_reserve_a as u128) * (time_elapsed_s as u128);
        self.price_b_cumulative_last =
            self.price_b_cumulative_last + (amount_reserve_a / amount_reserve_b as u128) * (time_elapsed_s as u128);
    };

    self.price_last_update_timestamp_s = current_time_s;
}

fun calculate_coin_amounts_to_provide<CoinA, CoinB>(
    self: &Pair,
    amount_a: u64,
    amount_b: u64,
    amount_a_min: u64,
    amount_b_min: u64,
): (u64, u64) {
    assert!(amount_a > 0 && amount_b > 0, EInsufficientAmountOfCoins);

    let self: &PairInner<CoinA, CoinB> = self.load_inner();
    let (reserve_a, reserve_b) = (
        balance::value(&self.coin_a_reserve),
        balance::value(&self.coin_b_reserve),
    );

    if (reserve_a == 0 && reserve_b == 0) {
        (amount_a, amount_b)
    } else {
        let amount_b_optimal = quote(amount_a, reserve_a, reserve_b);
        if (amount_b_optimal > amount_b) {
            assert!(amount_b_optimal >= amount_b_min, EInsufficientAmountOfCoinB);
            (amount_a, amount_b_optimal)
        } else {
            let amount_a_optimal = quote(amount_b, reserve_b, reserve_a);
            assert!(amount_a_optimal < amount_a);
            assert!(amount_a_optimal >= amount_a_min, EInsufficientAmountOfCoinA);
            (amount_a_optimal, amount_b)
        }
    }
}

fun calculate_lp_amount_to_mint<CoinA, CoinB>(self: &mut Pair, amount_a: u64, amount_b: u64): u64 {
    let self = self.load_inner_mut<CoinA, CoinB>();
    let (reserve_a, reserve_b) = (
        balance::value(&self.coin_a_reserve),
        balance::value(&self.coin_b_reserve),
    );
    let total_lp_supply = balance::supply_value(&self.lp_coin_supply);
    let mint_amount = if (total_lp_supply == 0) {
        balance::join(
            &mut self.lp_locked,
            balance::increase_supply(&mut self.lp_coin_supply, MINIMUM_LIQUIDITY),
        );
        ((std::u128::sqrt((amount_a as u128) * (amount_b as u128)) as u64) - MINIMUM_LIQUIDITY)
    } else {
        std::u64::min(
            (((amount_a as u128) * (total_lp_supply as u128)) / (reserve_a as u128)  as u64),
            (((amount_b as u128) * (total_lp_supply as u128)) / (reserve_b as u128)  as u64),
        )
    };
    assert!(mint_amount > 0, EInsufficientLPCoinMinted);

    mint_amount
}

fun calculate_amount_to_withdraw<CoinA, CoinB>(self: &mut Pair, amount_lp: u64): (u64, u64) {
    let self = self.load_inner_mut<CoinA, CoinB>();
    let (reserve_a, reserve_b) = (
        balance::value(&self.coin_a_reserve),
        balance::value(&self.coin_b_reserve),
    );
    let total_lp_supply = balance::supply_value(&self.lp_coin_supply);

    let withdraw_amount_a = ((amount_lp as u128) * (reserve_a as u128) / (total_lp_supply as u128) as u64);
    let withdraw_amount_b = ((amount_lp as u128) * (reserve_b as u128) / (total_lp_supply as u128) as u64);

    assert!(withdraw_amount_a > 0 && withdraw_amount_b > 0, EInsufficientLPCoinBurned);

    (withdraw_amount_a, withdraw_amount_b)
}

fun calculate_amount_out(amount_in: u64, amount_reserve_in: u64, amount_reserve_out: u64): u64 {
    assert!(amount_in > 0, EInsufficientAmountIn);
    assert!(amount_reserve_in > 0 && amount_reserve_out > 0, EInsufficientLiquidity);
    let amount_in_with_fee = (amount_in as u128) * 997;
    let numerator = amount_in_with_fee * (amount_reserve_out as u128);
    let denominator = (amount_reserve_in as u128) * 1000 + amount_in_with_fee;
    let amount_out = (numerator / denominator as u64);
    amount_out
}

fun calculate_amount_in(amount_out: u64, amount_reserve_in: u64, amount_reserve_out: u64): u64 {
    assert!(amount_out > 0, EInsufficientOutputAmount);
    assert!(amount_reserve_in > 0 && amount_reserve_out > 0, EInsufficientLiquidity);
    let numerator = (amount_reserve_in as u128) * (amount_out as u128) * 1000;
    let denominator = ((amount_reserve_out - amount_out) as u128) * 997;
    let amount_in = 1 + ((numerator / denominator) as u64);
    amount_in
}

/// Given an amount of an asset and pair reserves,
/// returns an equivalent amount of the other asset.
fun quote(amount_a: u64, amount_reserve_a: u64, amount_reserve_b: u64): u64 {
    assert!(amount_a > 0, EInsufficientAmount);
    assert!(amount_reserve_a > 0 && amount_reserve_b > 0, EInsufficientLiquidity);
    (((amount_a as u128) * (amount_reserve_b as u128)) / (amount_reserve_a as u128)  as u64)
}

fun load_inner<CoinA, CoinB>(self: &Pair): &PairInner<CoinA, CoinB> {
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