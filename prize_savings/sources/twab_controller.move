/// TODO: add explanation
module prize_savings::twab_controller;

use prize_savings::twab_info::{Self, TwabInfo, create_twab_info};
use sui::clock::{Clock};
use sui::vec_map::{Self, VecMap};

// === Structs ===
public struct TwabController has copy, store {
    twab_total: TwabInfo,
    twab_by_users: VecMap<address, TwabInfo>
}

// === Package Mutative Functions ===
public(package) fun create_twab_controller(clock: &Clock): TwabController {
    let twab_total = create_twab_info(clock);
    let twab_by_users = vec_map::empty<address, TwabInfo>();

    TwabController {
        twab_total,
        twab_by_users
    }
}

public(package) fun update(
    self: &mut TwabController,
    balance_change: u64,
    user_address: address,
    is_deposit: bool,
    clock: &Clock
) {
    self.twab_total.update(balance_change, is_deposit, clock);

    let twab_by_user = self.twab_by_users.get_mut(&user_address);
    twab_info::update(twab_by_user, balance_change, is_deposit, clock);
}

public(package) fun add_new_user_twab_info(self: &mut TwabController, user_address: address, clock: &Clock) {
    let twab_info = create_twab_info(clock);
    self.twab_by_users.insert(user_address, twab_info);
}

// === Package View Functions ===
public(package) fun is_new_user(self: &TwabController, user_address: address): bool {
    self.twab_by_users.contains(&user_address)
}