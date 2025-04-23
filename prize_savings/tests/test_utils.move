module prize_savings::test_utils;

use sui::clock::{Clock};
use sui::coin::{Self};
use sui::test_scenario::{Scenario, return_shared};

#[test_only]
public(package) fun deposit_coin_to_address<T>(value: u64, recipient: address, test: &mut Scenario) {
    let coin = coin::mint_for_testing<T>(value, test.ctx());
    transfer::public_transfer(coin, recipient);
}

#[test_only]
public(package) fun set_timestamp_s(test: &Scenario, timestamp_s: u64) {
    let mut clock = test.take_shared<Clock>();
    clock.set_for_testing(timestamp_s * 1000);
    return_shared(clock);
}