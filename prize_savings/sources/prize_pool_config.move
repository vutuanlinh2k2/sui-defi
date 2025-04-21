module prize_savings::prize_pool_config;

// === Errors ===
const EInvalidFrequency: u64 = 1;
const EEmptyTiers: u64 = 2;
const EInvalidTierConfig: u64 = 3;
const EInvalidTierWeight: u64 = 4;
const EInvalidTierWeightsSum: u64 = 5;
const EInvalidTierCount: u64 = 6;

// === Structs ===
public struct PrizePoolConfig has store, copy {
    prize_frequency_days: u8, // Eg. new pool_prize will be created once every 7 days
    prize_count_per_tier: vector<u8>,
    weight_per_tier: vector<u8>,
}

// === Public View Functions ===
public fun prize_frequency_days(self: &PrizePoolConfig): u8 {
    self.prize_frequency_days
}

public fun prize_count_per_tier(self: &PrizePoolConfig): vector<u8> {
    self.prize_count_per_tier
}

public fun weight_per_tier(self: &PrizePoolConfig): vector<u8> {
    self.weight_per_tier
}

// === Package Functions ===

public(package) fun create_pool_prize_config(
    prize_frequency_days: u8,
    prize_count_per_tier: vector<u8>,
    weight_per_tier: vector<u8>,
): PrizePoolConfig {
    let config = PrizePoolConfig {
        prize_frequency_days,
        prize_count_per_tier,
        weight_per_tier
    };

    assert_config(&config);

    config
}

// === Private Functions ===

fun assert_config(self: &PrizePoolConfig) {
    let prize_frequency_days = self.prize_frequency_days;
    let prize_count_per_tier = self.prize_count_per_tier;
    let weight_per_tier = self.weight_per_tier;

    assert!(prize_frequency_days > 0, EInvalidFrequency);
    assert!(prize_count_per_tier.length() > 0 && weight_per_tier.length() > 0, EEmptyTiers);
    assert!(prize_count_per_tier.length() == weight_per_tier.length(), EInvalidTierConfig);

    assert_prize_count_per_tier(prize_count_per_tier);
    assert_weight_per_tier(weight_per_tier);
}

fun assert_prize_count_per_tier(prize_count_per_tier: vector<u8>) {
    let length = prize_count_per_tier.length();
    let mut i = 0;

    while (i < length) {
        let tier_weight = *prize_count_per_tier.borrow(i);
        assert!(tier_weight > 0, EInvalidTierCount);
        i = i + 1;
    };
}

fun assert_weight_per_tier(weight_per_tier: vector<u8>) {
    let mut sum :u8 = 0;
    let length = weight_per_tier.length();
    
    let mut i = 0;
    while (i < length) {
        let tier_weight = *weight_per_tier.borrow(i);
        assert!(tier_weight > 0, EInvalidTierWeight);
        sum = sum + tier_weight;
        i = i + 1;
    };

    assert!(sum == 100, EInvalidTierWeightsSum);
}

// === Test Functions ===
#[test_only]
public fun create_test_prize_pool_config(): PrizePoolConfig {
    let mut prize_count_per_tier = vector::empty<u8>();
    prize_count_per_tier.push_back(1);
    prize_count_per_tier.push_back(4);
    prize_count_per_tier.push_back(16);

    let mut weight_per_tier = vector::empty<u8>();
    weight_per_tier.push_back(30);
    weight_per_tier.push_back(30);
    weight_per_tier.push_back(40);

    let prize_pool_config = PrizePoolConfig {
        prize_frequency_days: 1,
        prize_count_per_tier,
        weight_per_tier,
    }; 

    prize_pool_config.assert_config();

    prize_pool_config
}
