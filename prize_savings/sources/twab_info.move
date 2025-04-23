module prize_savings::twab_info;

use sui::clock::Clock;

public struct TwabInfo has store, copy, drop {
    balance_accumulation_last: u64,
    current_draw_initial_balance_accumulation: u64,
    last_update_timestamp_s: u64,
    balance_last: u64,
}

// === Public View Functions ===
public fun balance_accumulation_last(self: &TwabInfo): u64 {
    self.balance_accumulation_last
}

public fun current_draw_initial_balance_accumulation(self: &TwabInfo): u64 {
    self.current_draw_initial_balance_accumulation
}

public fun last_update_timestamp_s(self: &TwabInfo): u64 {
    self.last_update_timestamp_s
}

public fun balance_last(self: &TwabInfo): u64 {
    self.balance_last
}

// === Package Mutative Functions ===
public(package) fun create_twab_info(clock: &Clock): TwabInfo {
    TwabInfo {
        balance_accumulation_last: 0,
        last_update_timestamp_s: clock.timestamp_ms() / 1_000,
        current_draw_initial_balance_accumulation: 0,
        balance_last: 0,
    }
}

public(package) fun update(
    self: &mut TwabInfo,
    balance_change: u64,
    is_deposit: bool,
    current_draw_start_timestamp_s: u64,
    clock: &Clock,
) {
    if (self.last_update_timestamp_s < current_draw_start_timestamp_s) {
        self.current_draw_initial_balance_accumulation = self.balance_accumulation_last;
    };

    let current_time_s = clock.timestamp_ms() / 1000;
    let time_elapsed_s = current_time_s - self.last_update_timestamp_s;

    if (time_elapsed_s > 0 && self.balance_last > 0) {
        self.balance_accumulation_last = self.balance_accumulation_last + time_elapsed_s * self.balance_last;
        self.last_update_timestamp_s = current_time_s;
    };

    let updated_balance = if (is_deposit) {
        self.balance_last + balance_change
    } else {
        self.balance_last - balance_change
    };
    self.balance_last = updated_balance;
}

// === Package View Functions ===
public(package) fun get_twab(self: &TwabInfo, start_timestamp_s: u64, end_timestamp_s: u64): u64 {
    let last_update_timestamp_s = self.last_update_timestamp_s();

    assert!(end_timestamp_s > last_update_timestamp_s);
    let time_elapse_s = end_timestamp_s - last_update_timestamp_s;

    let current_balance_accumulation =
        self.balance_accumulation_last() + self.balance_last() * time_elapse_s;

    let twab = (
        current_balance_accumulation - self.current_draw_initial_balance_accumulation()
    ) / (end_timestamp_s - start_timestamp_s);

    twab
}

// === Test Functions ===
#[test_only]
public(package) fun create_test_twab_info(
    balance_accumulation_last: u64,
    current_draw_initial_balance_accumulation: u64,
    last_update_timestamp_s: u64,
    balance_last: u64,
): TwabInfo {
    TwabInfo {
        balance_accumulation_last,
        current_draw_initial_balance_accumulation,
        last_update_timestamp_s,
        balance_last,
    }
}