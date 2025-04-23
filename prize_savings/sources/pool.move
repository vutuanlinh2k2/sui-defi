/// A Pool that connect to a Reserve in Protocol Simulator
/// In real world, there will be a module for interact that interact with
/// different protocols (suilend_pool.move, navi_pool.move)
module prize_savings::pool;

use prize_savings::decimal::{Decimal, floor, mul, div, from};
use prize_savings::prize_pool_config::{PrizePoolConfig};
use prize_savings::prize_pool::{PrizePool, create_and_share_prize_pool};
use prize_savings::protocol::{Reserve, YBToken};
use prize_savings::registry::{AdminCap};
use prize_savings::twab_controller::{TwabController, create_twab_controller};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::clock::{Clock};
use sui::random::{Random};

// === Errors ===
const ENewDrawNotReady: u64 = 1;
const EPrizePoolNotExpired: u64 = 2;

// === Structs ===
public struct Pool<phantom T> has key {
    id: UID,
    reserve_id: ID,
    draw_count: u64,
    prize_pool_config: PrizePoolConfig,
    twab_controller: TwabController,
    yb_balances: Balance<YBToken<T>>,
    p_token_supply: Supply<PToken<T>>,
    deposited_amount: u64,
    current_draw_start_timestamp_s: u64,
    reserve_balances: Balance<T>, // Storage of unclaimed prizes from past Prize Pool to use for the next draw
}

// Represent user's share in the pool
public struct PToken<phantom T> has drop {}

// === Public View Functions ===
public fun reserve_id<T>(self: &Pool<T>): ID {
    self.reserve_id
}

public fun yb_balances_amount<T>(self: &Pool<T>): u64 {
    balance::value(&self.yb_balances)
}

public fun p_token_supply_amount<T>(self: &Pool<T>): u64 {
    balance::supply_value(&self.p_token_supply)
}

public fun prize_pool_config<T>(self: &Pool<T>): PrizePoolConfig {
    self.prize_pool_config
}

public fun current_draw_start_timestamp_s<T>(self: &Pool<T>): u64 {
    self.current_draw_start_timestamp_s
}

public fun twab_controller<T>(self: &Pool<T>): TwabController {
    self.twab_controller
}

public fun draw_count<T>(self: &Pool<T>): u64 {
    self.draw_count
}

public fun deposited_amount<T>(self: &Pool<T>): u64 {
    self.deposited_amount
}

public fun p_yb_ratio<T>(self: &Pool<T>): Decimal {
    let p_token_supply_amount = balance::supply_value(&self.p_token_supply);
    if (p_token_supply_amount == 0) {
        from(1)
    } else {
        let yb_balance = balance::value(&self.yb_balances);
        div(
            from(yb_balance),
            from(p_token_supply_amount),
        )
    }
}

// === Public Mutative Functions ===

public fun deposit_and_mint_p_token<T>(
    self: &mut Pool<T>,
    reserve: &mut Reserve<T>, 
    tokens: Coin<T>,
    user_address: address,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let token_amount = coin::value(&tokens);
    let yb_tokens = reserve.deposit_and_mint_yb_token(tokens, ctx);
    let yb_amount = coin::value(&yb_tokens);

    let p_amount = floor(
        div(
            from(yb_amount),
            self.p_yb_ratio()
        )
    );

    let twab_controller = &mut self.twab_controller;
    if (twab_controller.is_new_user(user_address)) {
        twab_controller.add_new_user_twab_info(user_address, clock);
    };

    twab_controller.update(
        p_amount,
        user_address, 
        true,
        self.current_draw_start_timestamp_s,
        clock
    );

    self.deposited_amount = self.deposited_amount + token_amount;

    balance::join(&mut self.yb_balances, coin::into_balance(yb_tokens));

    let p_tokens = coin::from_balance(
        balance::increase_supply(&mut self.p_token_supply, p_amount), 
        ctx
    );
    transfer::public_transfer(p_tokens, user_address);  
}

public fun withdraw_and_burn_p_token<T>(
    self: &mut Pool<T>,
    reserve: &mut Reserve<T>,   
    p_tokens: Coin<PToken<T>>, 
    user_address: address,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let p_amount = coin::value(&p_tokens);

    let yb_amount_to_redeem = floor(
        mul(
            from(p_amount),
            self.p_yb_ratio()
        )
    );

    let twab_controller = &mut self.twab_controller;

    twab_controller.update(
        p_amount, 
        user_address, 
        false,
        self.current_draw_start_timestamp_s,
        clock
    );

    let yb_tokens = coin::from_balance(
        balance::split(&mut self.yb_balances, yb_amount_to_redeem),
        ctx
    );

    let tokens = reserve.redeem_yb_token_and_withdraw(yb_tokens, ctx);

    self.deposited_amount = self.deposited_amount - tokens.value();

    transfer::public_transfer(tokens, user_address);
    balance::decrease_supply(&mut self.p_token_supply, coin::into_balance(p_tokens));
}

#[allow(lint(public_random))]
public fun new_draw_and_prize_pool<T>(
    self: &mut Pool<T>,
    reserve: &mut Reserve<T>,
    clock: &Clock,
    r: &Random,
    ctx: &mut TxContext
): ID {
    let current_timestamp_s = clock.timestamp_ms() / 1_000;
    let prize_frequency_days = self.prize_pool_config.prize_frequency_days();
    let prize_count_per_tier = self.prize_pool_config.prize_count_per_tier();
    assert!(
        self.current_draw_start_timestamp_s + (prize_frequency_days as u64) * 86_400 <= current_timestamp_s,
        ENewDrawNotReady
    );
    let current_yb_token_ratio = reserve.yb_token_ratio();
    let yb_token_amount_to_redeem = get_yb_token_amount_to_redeem_to_get_prize_tokens(
        self, 
        current_yb_token_ratio
    );
    let mut prize_balances = reserve.redeem_yb_token_and_withdraw(
        coin::from_balance(self.yb_balances.split(yb_token_amount_to_redeem), ctx), 
        ctx
    ).into_balance();

    // Add unclaimed prizes from past draw to the new prize pool
    let reserve_balances_amount = self.reserve_balances.value();
    prize_balances.join(self.reserve_balances.split(reserve_balances_amount));

    let total_prize_amount = balance::value(&prize_balances);

    let prize_per_winner_per_tier = get_prize_amount_per_winner_per_tier(
        total_prize_amount,
        &self.prize_pool_config
    );

    let draw_id = self.draw_count + 1;

    let prize_pool_id = create_and_share_prize_pool(
        object::id(self),
        draw_id,
        prize_count_per_tier,
        prize_per_winner_per_tier,
        self.prize_pool_config.expire_timeframe_days(),
        self.prize_pool_config.tier_frequency_weights(),
        self.twab_controller,
        generate_draw_random_number(r, ctx),
        self.current_draw_start_timestamp_s,
        current_timestamp_s,
        prize_balances,
        ctx
    );
    
    // Update for next draw
    self.draw_count = draw_id;
    self.current_draw_start_timestamp_s = current_timestamp_s;

    prize_pool_id
}

public fun get_unclaimed_from_prize_pool<T>(
    self: &mut Pool<T>, 
    prize_pool: &mut PrizePool<T>, 
    clock: &Clock
) {
  assert!(
    clock.timestamp_ms() / 1_000 > prize_pool.end_timestamp_s() + (prize_pool.expire_timeframe_days() as u64) * 86_400, 
    EPrizePoolNotExpired
    );

    balance::join(&mut self.reserve_balances, prize_pool.prize_balances());
}

// === Admin Functions ===
public fun create_new_pool<T>(
    reserve: &Reserve<T>, 
    prize_pool_config: PrizePoolConfig, 
    _cap: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext
): ID {
    let id = object::new(ctx);
    let twab_controller = create_twab_controller(clock);
    let pool= Pool {
        id,
        reserve_id: object::id(reserve),
        prize_pool_config,
        twab_controller,
        deposited_amount: 0,
        yb_balances: balance::zero<YBToken<T>>(),
        p_token_supply: balance::create_supply(PToken<T> {}),
        current_draw_start_timestamp_s: clock.timestamp_ms() / 1_000,
        draw_count: 0,
        reserve_balances: balance::zero<T>(),
    };

    let id = object::id(&pool);
    transfer::share_object(pool);

    id
}

// === Private Functions ===
fun generate_draw_random_number(r: &Random, ctx: &mut TxContext): u256 {
    let mut random_generator = r.new_generator(ctx);

    random_generator.generate_u256()
}

fun get_yb_token_amount_to_redeem_to_get_prize_tokens<T>(
    self: &Pool<T>,
    current_yb_token_ratio: Decimal
): u64 {
    let yb_balance_amount_to_token_value = floor(
        mul(from(self.yb_balances.value()) ,current_yb_token_ratio),
    );
    let value_increase = yb_balance_amount_to_token_value - self.deposited_amount;
    let amount_to_redeem = floor(div(from(value_increase), current_yb_token_ratio));

    amount_to_redeem
}

fun get_prize_amount_per_winner_per_tier(total_amount: u64, prize_pool_config: &PrizePoolConfig): vector<u64> {
    let mut prize_per_winner_per_tier = vector::empty<u64>();

    let mut i = 0;
    while (i < prize_pool_config.prize_count_per_tier().length()) {
        let tier_weight = *prize_pool_config.weight_per_tier().borrow(i);
        let count = *prize_pool_config.prize_count_per_tier().borrow(i);
        let total_prize_per_tier = total_amount * (tier_weight as u64) / 100;
        let prize_per_winner = total_prize_per_tier / (count as u64);
        prize_per_winner_per_tier.push_back(prize_per_winner);
        i = i + 1;
    };

    prize_per_winner_per_tier
}

// === Test Functions ===
#[test_only]
public fun create_test_pool<T>(
    reserve: &Reserve<T>, 
    prize_pool_config: PrizePoolConfig,
    clock: &Clock,
    ctx: &mut TxContext
): ID {
    let id = object::new(ctx);
    let twab_controller = create_twab_controller(clock);
    let pool= Pool {
        id,
        reserve_id: object::id(reserve),
        prize_pool_config,
        twab_controller,
        deposited_amount: 0,
        yb_balances: balance::zero<YBToken<T>>(),
        p_token_supply: balance::create_supply(PToken<T> {}),
        current_draw_start_timestamp_s: clock.timestamp_ms() / 1_000,
        draw_count: 0,
        reserve_balances: balance::zero<T>(),
    };

    let id = object::id(&pool);
    transfer::share_object(pool);

    id
}