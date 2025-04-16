module prize_savings::test_utils;

use sui::coin::{Self};
use sui::test_scenario::{Scenario};

#[test_only]
public(package) fun deposit_coin_to_address<T>(value: u64, recipient: address, test: &mut Scenario) {
    let coin = coin::mint_for_testing<T>(value, test.ctx());
    transfer::public_transfer(coin, recipient);
}