/// Keep track of pool's average balance and user's average balance
module prize_savings::twab_controller;

use prize_savings::twab_info::{TwabInfo, create_twab_info, create_test_twab_info};
use sui::clock::Clock;
use sui::vec_map::{Self, VecMap};

// === Structs ===
public struct TwabController has copy, store, drop {
    twab_total: TwabInfo,
    twab_by_users: VecMap<address, TwabInfo>,
}

// === Public View Functions ===
public fun twab_total(self: &TwabController): &TwabInfo {
    &self.twab_total
}

public fun twab_by_users(self: &TwabController): &VecMap<address, TwabInfo> {
    &self.twab_by_users
}

// === Package Mutative Functions ===
public(package) fun create_twab_controller(clock: &Clock): TwabController {
    let twab_total = create_twab_info(clock);
    let twab_by_users = vec_map::empty<address, TwabInfo>();

    TwabController {
        twab_total,
        twab_by_users,
    }
}

public(package) fun update(
    self: &mut TwabController,
    balance_change: u64,
    user_address: address,
    is_deposit: bool,
    current_draw_start_timestamp_s: u64,
    clock: &Clock,
) {
    self.twab_total.update(
        balance_change,
        is_deposit,
        current_draw_start_timestamp_s,
        clock,
    );

    let twab_by_user = self.twab_by_users.get_mut(&user_address);
    twab_by_user.update(
        balance_change,
        is_deposit,
        current_draw_start_timestamp_s,
        clock,
    );
}

public(package) fun add_new_user_twab_info(
    self: &mut TwabController,
    user_address: address,
    clock: &Clock,
) {
    let twab_info = create_twab_info(clock);
    self.twab_by_users.insert(user_address, twab_info);
}

// === Package View Functions ===
public(package) fun get_twab_total(
    self: &TwabController,
    start_timestamp_s: u64,
    end_timestamp_s: u64,
): u64 {
    let twab_total_info = &self.twab_total;
    twab_total_info.get_twab(start_timestamp_s, end_timestamp_s)
}

public(package) fun get_twab_by_user(
    self: &TwabController,
    user_address: address,
    start_timestamp_s: u64,
    end_timestamp_s: u64,
): u64 {
    let twab_info = self.twab_by_users.get(&user_address);
    twab_info.get_twab(start_timestamp_s, end_timestamp_s)
}

public(package) fun is_new_user(self: &TwabController, user_address: address): bool {
    !self.twab_by_users.contains(&user_address)
}

// === Test Functions ===
#[test_only]
public(package) fun create_test_ready_twab_controller(): TwabController {
    let alice: address = @0xAAAA;
    let bob: address = @0xBBBB;

    let twab_total = create_test_twab_info(288333333295000, 0, 75000, 3666666666);
    let twab_alice = create_test_twab_info(161666666645000, 0, 75000, 1333333333);
    let twab_bob = create_test_twab_info(10000000000000, 0, 25000, 2333333333);

    let mut twab_by_users = vec_map::empty<address, TwabInfo>();
    twab_by_users.insert(alice, twab_alice);
    twab_by_users.insert(bob, twab_bob);

    TwabController {
        twab_total,
        twab_by_users,
    }
}
