module prize_savings::prize_pool;

use prize_savings::twab_controller::{TwabController, create_test_ready_twab_controller};
use sui::balance::{Self, Balance};
use sui::bcs;
use sui::clock::Clock;
use sui::coin;
use sui::hash::keccak256;
use sui::vec_map::{Self, VecMap};
use std::debug::print;

// === Errors ===
const EInvalidDrawId: u64 = 1;
const EInvalidTierIndexInput: u64 = 2;
const EDeadlinePassed: u64 = 3;
const EPrizeAmountZero: u64 = 4;
const ENotWinner: u64 = 5;
const ENotEligible: u64 = 6;
const EAlreadyClaimed: u64 = 7;

// === Structs ===
public struct PrizePool<phantom T> has key {
    id: UID,
    pool_id: ID,
    draw_id: u64,
    prize_per_winner_per_tier: vector<u64>,
    prize_count_per_tier: vector<u8>,
    expire_timeframe_days: u8,
    tier_frequency_weights: vector<u8>,
    twab_controller_snapshot: TwabController,
    draw_random_number: u256,
    start_timestamp_s: u64,
    end_timestamp_s: u64,
    prize_balances: Balance<T>,
    claimed_prizes: VecMap<u64, VecMap<u64, bool>>, // tier → prize_index → boolean
}

// === Public Mutative Functions ===
public fun claim_prize<T>(
    self: &mut PrizePool<T>,
    user_address: address,
    tier: u64,
    prize_index: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(
        clock.timestamp_ms() / 1000 < self.end_timestamp_s + (self.expire_timeframe_days as u64) * 86_400,
        EDeadlinePassed,
    );

    let prize_amount = *self.prize_per_winner_per_tier.borrow(tier);
    assert!(prize_amount > 0, EPrizeAmountZero);

    assert!(self.is_winner(user_address, tier, prize_index), ENotWinner);

    if (self.claimed_prizes.contains(&tier)) {
        let tier_prize_index_map = self.claimed_prizes.get(&tier);
        if (tier_prize_index_map.contains(&prize_index)) {
            assert!(false, EAlreadyClaimed);
        };
    };

    let reward = coin::from_balance(self.prize_balances.split(prize_amount), ctx);
    transfer::public_transfer(reward, user_address);

    // Update claimed_prizes map
    if (!self.claimed_prizes.contains(&tier)) {
        self.claimed_prizes.insert(tier, vec_map::empty<u64, bool>());
    };
    let tier_prize_index_map = self.claimed_prizes.get_mut(&tier);
    tier_prize_index_map.insert(prize_index, true);
}

// === Public View Functions ===
public fun is_winner<T>(
    self: &PrizePool<T>,
    user_address: address,
    tier: u64,
    prize_index: u64,
): bool {
    assert!(self.draw_id > 0, EInvalidDrawId);

    let num_of_tiers = self.assert_and_get_num_of_tiers();
    assert!(tier < num_of_tiers, EInvalidTierIndexInput);

    let tier_prize_count = *self.prize_count_per_tier.borrow(tier);
    print(&tier_prize_count);
    assert!(prize_index < (tier_prize_count as u64), EInvalidTierIndexInput);

    let user_specific_random_number = calculate_pseudo_random_number(
        self.draw_id,
        self.pool_id,
        user_address,
        tier,
        prize_index,
        self.draw_random_number,
    );
    print(&user_specific_random_number);

    let tier_frequency_weight = *self.tier_frequency_weights.borrow(tier);

    let twab_controller_snapshot = self.twab_controller_snapshot;
    assert!(
        twab_controller_snapshot.twab_by_users().contains(&user_address),
        ENotEligible,
    );

    let twab_total = twab_controller_snapshot.get_twab_total(
        self.start_timestamp_s,
        self.end_timestamp_s,
    );

    let twab_by_user = twab_controller_snapshot.get_twab_by_user(
        user_address,
        self.start_timestamp_s,
        self.end_timestamp_s,
    );
    assert!(twab_by_user > 0, ENotEligible);

    let winning_zone = twab_by_user / (tier_frequency_weight as u64);

    let is_winner = (user_specific_random_number % (twab_total as u256)) < (winning_zone as u256);

    is_winner
}

public fun pool_id<T>(self: &PrizePool<T>): ID {
    self.pool_id
}

public fun draw_id<T>(self: &PrizePool<T>): u64 {
    self.draw_id
}

public fun prize_per_winner_per_tier<T>(self: &PrizePool<T>): vector<u64> {
    self.prize_per_winner_per_tier
}

public fun prize_count_per_tier<T>(self: &PrizePool<T>): vector<u8> {
    self.prize_count_per_tier
}

public fun twab_controller_snapshot<T>(self: &PrizePool<T>): TwabController {
    self.twab_controller_snapshot
}

public fun draw_random_number<T>(self: &PrizePool<T>): u256 {
    self.draw_random_number
}

public fun start_timestamp_s<T>(self: &PrizePool<T>): u64 {
    self.start_timestamp_s
}

public fun end_timestamp_s<T>(self: &PrizePool<T>): u64 {
    self.end_timestamp_s
}

public fun prize_balances_amount<T>(self: &PrizePool<T>): u64 {
    self.prize_balances.value()
}

public fun expire_timeframe_days<T>(self: &PrizePool<T>): u8 {
    self.expire_timeframe_days
}

// === Package Functions ===
public(package) fun create_and_share_prize_pool<T>(
    pool_id: ID,
    draw_id: u64,
    prize_count_per_tier: vector<u8>,
    prize_per_winner_per_tier: vector<u64>,
    expire_timeframe_days: u8,
    tier_frequency_weights: vector<u8>,
    twab_controller_snapshot: TwabController,
    draw_random_number: u256,
    start_timestamp_s: u64,
    end_timestamp_s: u64,
    prize_balances: Balance<T>,
    ctx: &mut TxContext,
): ID {
    let prize_pool = PrizePool {
        id: object::new(ctx),
        pool_id,
        draw_id,
        prize_count_per_tier,
        prize_per_winner_per_tier,
        twab_controller_snapshot,
        draw_random_number,
        prize_balances,
        expire_timeframe_days,
        tier_frequency_weights,
        start_timestamp_s,
        end_timestamp_s,
        claimed_prizes: vec_map::empty<u64, VecMap<u64, bool>>(),
    };

    let id = object::id(&prize_pool);
    transfer::share_object(prize_pool);

    id
}

public(package) fun prize_balances<T>(self: &mut PrizePool<T>): Balance<T> {
    let prize_balances_amount = self.prize_balances.value();
    self.prize_balances.split(prize_balances_amount)
}

// === Private Functions ===
fun assert_and_get_num_of_tiers<T>(self: &PrizePool<T>): u64 {
    self.assert_tier_structure();
    self.prize_count_per_tier.length()
}

fun assert_tier_structure<T>(self: &PrizePool<T>) {
    let prize_count_per_tier_length = self.prize_count_per_tier.length();
    let prize_per_winner_per_tier_length = self.prize_per_winner_per_tier.length();
    let tier_frequency_weights_length = self.tier_frequency_weights.length();

    assert!(
        prize_count_per_tier_length > 0 &&
            prize_per_winner_per_tier_length > 0 &&
            tier_frequency_weights_length > 0,
    );
    assert!(prize_count_per_tier_length == prize_per_winner_per_tier_length);
    assert!(prize_count_per_tier_length == self.tier_frequency_weights.length());
}

/// Calculates a pseudo-random number unique to the inputs
fun calculate_pseudo_random_number(
    draw_id: u64,
    pool_id: ID,
    user_address: address,
    tier: u64,
    prize_index: u64,
    draw_random_number: u256,
): u256 {
    let mut bytes = vector::empty<u8>();

    vector::append(&mut bytes, bcs::to_bytes(&draw_id));
    vector::append(&mut bytes, pool_id.to_bytes());
    vector::append(&mut bytes, user_address.to_bytes());
    vector::append(&mut bytes, bcs::to_bytes(&tier));
    vector::append(&mut bytes, bcs::to_bytes(&prize_index));
    vector::append(&mut bytes, bcs::to_bytes(&draw_random_number));

    let hash = keccak256(&bytes);
    let mut bcs = bcs::new(hash);
    bcs::peel_u256(&mut bcs)
}

// === Test Functions ===
#[test_only]
public(package) fun create_test_prize_pool<T>(ctx: &mut TxContext): ID {
  let mut prize_per_winner_per_tier = vector::empty<u64>();
  prize_per_winner_per_tier.push_back(150_000_000);
  prize_per_winner_per_tier.push_back(37_500_000);
  prize_per_winner_per_tier.push_back(12_500_000);

  let mut prize_count_per_tier = vector::empty<u8>();
  prize_count_per_tier.push_back(1);
  prize_count_per_tier.push_back(4);
  prize_count_per_tier.push_back(16);

  let mut tier_frequency_weights = vector::empty<u8>();
  tier_frequency_weights.push_back(10);
  tier_frequency_weights.push_back(5);
  tier_frequency_weights.push_back(1);

  let twab_controller_snapshot = create_test_ready_twab_controller();
  let id = object::new(ctx);

  let prize_pool = PrizePool {
    pool_id: *id.as_inner(),
    id,
    draw_id: 1,
    claimed_prizes: vec_map::empty<u64, VecMap<u64, bool>>(),
    draw_random_number: 115017734510397680132393617573150939251716540686415307084561143230928494569592,
    end_timestamp_s: 86400,
    expire_timeframe_days: 1,
    start_timestamp_s: 0,
    prize_per_winner_per_tier,
    prize_count_per_tier,
    tier_frequency_weights,
    prize_balances: balance::create_for_testing<T>(500_000_000),
    twab_controller_snapshot
  };

  let id = object::id(&prize_pool);
  transfer::share_object(prize_pool);

  id
}