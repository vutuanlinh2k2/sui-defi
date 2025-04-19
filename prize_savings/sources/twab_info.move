/// TODO: add explanation
module prize_savings::twab_info;

use sui::clock::Clock;

public struct TwabInfo has store, copy {
    balance_accumulation_last: u64,
    balance_accumulation_from_last_draw: u64,
    balance_last_update_timestamp_s: u64,
    balance_last: u64
}

public(package) fun create_twab_info(clock: &Clock): TwabInfo {
    let twab_info = TwabInfo {
        balance_accumulation_last: 0,
        balance_last_update_timestamp_s: clock.timestamp_ms() / 1_000,
        balance_accumulation_from_last_draw: 0,
        balance_last: 0
    };
    twab_info
}

public(package) fun update(
    self: &mut TwabInfo, 
    balance_change: u64, 
    is_deposit: bool, 
    clock: &Clock
) {
    let updated_balance = if (is_deposit) {
        self.balance_last + balance_change
    } else {
        self.balance_last - balance_change
    };
    self.balance_last = updated_balance;

    let current_time_s = clock.timestamp_ms() / 1000;
    let time_elapsed_s = current_time_s - self.balance_last_update_timestamp_s;

    if (time_elapsed_s > 0 && updated_balance > 0) {
        self.balance_accumulation_last = self.balance_accumulation_last + time_elapsed_s * updated_balance;
        self.balance_last_update_timestamp_s = current_time_s;
    };
}