/// A Pool that connect to a Reserve in Protocol Simulator
/// In real world, there will be a module for interact that interact with 
/// different protocols (suilend_pool.move, navi_pool.move)
module prize_savings::pool;

use prize_savings::prize_pool_config::{PrizePoolConfig};
use prize_savings::protocol_simulator::{PSReserve, YBToken};
use prize_savings::registry::{AdminCap};
use prize_savings::twab_controller::{TwabController, create_twab_controller};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin};
use sui::clock::{Clock};

// === Structs ===
public struct Pool<phantom T> has key {
    id: UID,
    reserve_id: ID,
    yb_balances: Balance<YBToken<T>>,
    p_token_supply: Supply<PToken<T>>,
    prize_pool_config: PrizePoolConfig,
    current_draw_start_timestamp_s: u64,
    twab_controller: TwabController
}

public struct PToken<phantom T> has drop {} // Represent user's share in the pool

// === Public Mutative Functions ===

#[allow(lint(self_transfer))]
public fun deposit_to_pool_and_mint_p_token<T>(
    self: &mut Pool<T>,
    reserve: &mut PSReserve<T>, 
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
    reserve: &mut PSReserve<T>,   
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

public fun check_and_add_new_draw<T>(self: &mut Pool<T>, clock: &Clock) {
    // TODO
}

// === Public View Functions ===
public fun reserve_id<T>(self: &Pool<T>): ID {
    self.reserve_id
}

// === Admin Functions ===
public fun create_new_pool<T>(
    reserve_id: ID, 
    prize_pool_config: PrizePoolConfig, 
    _cap: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext
): ID {
    let id = object::new(ctx);
    let twab_controller = create_twab_controller(clock);
    let pool= Pool {
        id,
        reserve_id,
        yb_balances: balance::zero<YBToken<T>>(),
        p_token_supply: balance::create_supply(PToken<T> {}),
        prize_pool_config,
        current_draw_start_timestamp_s: clock.timestamp_ms() / 1_000,
        twab_controller
    };

    let id = object::id(&pool);
    transfer::share_object(pool);

    id
}