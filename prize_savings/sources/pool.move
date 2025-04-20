/// A Pool that connect to a Reserve in Protocol Simulator
/// In real world, there will be a module for interact that interact with
/// different protocols (suilend_pool.move, navi_pool.move)
module prize_savings::pool;

use prize_savings::decimal::{Decimal, ceil, mul, div, from};
use prize_savings::prize_pool_config::{PrizePoolConfig};
use prize_savings::prize_pool::{create_prize_pool};
use prize_savings::protocol::{Reserve, YBToken};
use prize_savings::registry::{AdminCap};
use prize_savings::twab_controller::{TwabController, create_twab_controller};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::clock::{Clock};
use sui::random::{Random};

// === Errors ===
const ENewDrawNotReady: u64 = 1;

// === Structs ===
public struct Pool<phantom T> has key {
    id: UID,
    reserve_id: ID,
    yb_balances: Balance<YBToken<T>>,
    p_token_supply: Supply<PToken<T>>,
    prize_pool_config: PrizePoolConfig,
    current_draw_start_timestamp_s: u64,
    current_draw_initial_yb_token_ratio: Decimal,
    twab_controller: TwabController,
    draw_count: u64,
}

// Represent user's share in the pool
public struct PToken<phantom T> has drop {}

// === Public Mutative Functions ===
#[allow(lint(self_transfer))]
public fun deposit_to_pool_and_mint_p_token<T>(
    self: &mut Pool<T>,
    reserve: &mut Reserve<T>, 
    tokens: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let yb_tokens = reserve.deposit_and_mint_yb_token(tokens, ctx);
    let yb_amount = coin::value(&yb_tokens);
    let p_amount = yb_amount;
    balance::join(&mut self.yb_balances, coin::into_balance(yb_tokens));
    let p_tokens = coin::from_balance(
        balance::increase_supply(&mut self.p_token_supply, p_amount), 
        ctx
    );

    let sender = ctx.sender();
    let twab_controller = &mut self.twab_controller;
    if (twab_controller.is_new_user(sender)) {
        twab_controller.add_new_user_twab_info(sender, clock);
    };

    twab_controller.update(p_amount, sender, true, clock);

    transfer::public_transfer(p_tokens, sender);  
}

#[allow(lint(self_transfer))]
public fun withdraw_from_pool_and_burn_p_token<T>(
    self: &mut Pool<T>,
    reserve: &mut Reserve<T>,   
    p_tokens: Coin<PToken<T>>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let p_amount = coin::value(&p_tokens);
    balance::decrease_supply(&mut self.p_token_supply, coin::into_balance(p_tokens));
    let yb_tokens = coin::from_balance(
        balance::split(&mut self.yb_balances, p_amount),
        ctx
    );
    let sender = ctx.sender();
    let twab_controller = &mut self.twab_controller;

    twab_controller.update(p_amount, sender, false, clock);

    let tokens = reserve.redeem_yb_token_and_withdraw(yb_tokens, ctx);
    transfer::public_transfer(tokens, sender);
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
        self.current_draw_start_timestamp_s + (prize_frequency_days as u64) * 86_400 < current_timestamp_s,
        ENewDrawNotReady
    );
    let current_yb_token_ratio = reserve.yb_token_ratio();
    let yb_token_amount_to_redeem = get_yb_token_amount_to_redeem_to_get_prize_tokens(
        self, 
        current_yb_token_ratio
    );
    let prize_balances = reserve.redeem_yb_token_and_withdraw(
        coin::from_balance(self.yb_balances.split(yb_token_amount_to_redeem), ctx), 
        ctx
    ).into_balance();

    let total_prize_amount = balance::value(&prize_balances);

    let prize_per_winner_per_tier = get_prize_amount_per_winner_per_tier(
        total_prize_amount,
        &self.prize_pool_config
    );

    let mut i = 0;
    while (i < prize_count_per_tier.length()) {
        
        i = i + 1;
    };

    // Update for next draw
    self.current_draw_start_timestamp_s = current_timestamp_s;
    self.draw_count = self.draw_count + 1;
    self.current_draw_initial_yb_token_ratio = current_yb_token_ratio;

    let prize_pool_id = create_prize_pool(
        object::id(self),
        self.draw_count,
        prize_count_per_tier,
        prize_per_winner_per_tier,
        self.twab_controller,
        generate_draw_random_number(r, ctx),
        prize_balances,
        ctx
    );

    prize_pool_id
}

// === Public View Functions ===
public fun reserve_id<T>(self: &Pool<T>): ID {
    self.reserve_id
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
        yb_balances: balance::zero<YBToken<T>>(),
        p_token_supply: balance::create_supply(PToken<T> {}),
        prize_pool_config,
        current_draw_start_timestamp_s: clock.timestamp_ms() / 1_000,
        current_draw_initial_yb_token_ratio: reserve.yb_token_ratio(),
        twab_controller,
        draw_count: 0,
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
    let yb_balance_amount = balance::value(&self.yb_balances);

    // balance - old_ratio x balance / new_ratio
    let amount_to_redeem = yb_balance_amount - ceil(
        div(mul(self.current_draw_initial_yb_token_ratio, from(yb_balance_amount)),
        current_yb_token_ratio)
    );
    amount_to_redeem
}

fun get_prize_amount_per_winner_per_tier(total_amount: u64, prize_pool_config: &PrizePoolConfig): vector<u64> {
    let mut prize_per_winner_per_tier = vector::empty<u64>();

    let mut i = 0;
    while (i < prize_pool_config.prize_count_per_tier().length()) {
        let tier_weight = *prize_pool_config.weight_per_tier().borrow(i);
        let count = *prize_pool_config.prize_count_per_tier().borrow(i);
        let total_prize_per_tier = total_amount * (tier_weight as u64);
        let prize_per_winner = total_prize_per_tier / (count as u64);
        prize_per_winner_per_tier.push_back(prize_per_winner);
        i = i + 1;
    };

    prize_per_winner_per_tier
}