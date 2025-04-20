/// TODO: add explanation
module prize_savings::twab_info;

use sui::clock::Clock;

public struct TwabInfo has store, copy {
    balance_accumulation_last: u64,
    current_draw_initial_balance_accumulation: u64,
    last_update_timestamp_s: u64,
    balance_last: u64
}

public(package) fun create_twab_info(clock: &Clock): TwabInfo {
    let twab_info = TwabInfo {
        balance_accumulation_last: 0,
        last_update_timestamp_s: clock.timestamp_ms() / 1_000,
        current_draw_initial_balance_accumulation: 0,
        balance_last: 0
    };
    twab_info
}

public(package) fun update(
    self: &mut TwabInfo, 
    balance_change: u64, 
    is_deposit: bool,
    current_draw_start_timestamp_s: u64,
    clock: &Clock
) {
    let updated_balance = if (is_deposit) {
        self.balance_last + balance_change
    } else {
        self.balance_last - balance_change
    };
    self.balance_last = updated_balance;

    if (self.last_update_timestamp_s < current_draw_start_timestamp_s) {
        self.current_draw_initial_balance_accumulation = self.balance_accumulation_last;
    };

    let current_time_s = clock.timestamp_ms() / 1000;
    let time_elapsed_s = current_time_s - self.last_update_timestamp_s;

    if (time_elapsed_s > 0 && updated_balance > 0) {
        self.balance_accumulation_last = self.balance_accumulation_last + time_elapsed_s * updated_balance;
        self.last_update_timestamp_s = current_time_s;
    };
}