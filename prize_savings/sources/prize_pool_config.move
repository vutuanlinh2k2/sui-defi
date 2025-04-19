module prize_savings::prize_pool_config;

// === Errors ===
const EInvalidFrequency: u64 = 1;
const EEmptyTiers: u64 = 2;
const EInvalidTierConfig: u64 = 3;
const EInvalidTierWeight: u64 = 4;
const EInvalidTierWeightsSum: u64 = 5;
const EInvalidTierCount: u64 = 6;

// === Structs ===
public struct PrizePoolConfig has store {
    prize_frequency_days: u8, // Eg. new pool_prize will be created once every 7 days
    tier_prize_counts: vector<u8>,
    tier_prize_weights: vector<u8>,
}

// === Package Functions ===

public(package) fun create_pool_prize_config(
    prize_frequency_days: u8,
    tier_prize_counts: vector<u8>,
    tier_prize_weights: vector<u8>,
): PrizePoolConfig {
    let config = PrizePoolConfig {
        prize_frequency_days,
        tier_prize_counts,
        tier_prize_weights
    };

    assert_pool_prize_config(&config);

    config
}

// === Private Functions ===

fun assert_pool_prize_config(self: &PrizePoolConfig) {
    let prize_frequency_days = self.prize_frequency_days;
    let tier_prize_counts = self.tier_prize_counts;
    let tier_prize_weights = self.tier_prize_weights;

    assert!(prize_frequency_days > 0, EInvalidFrequency);
    assert!(tier_prize_counts.length() > 0 && tier_prize_weights.length() > 0, EEmptyTiers);
    assert!(tier_prize_counts.length() == tier_prize_weights.length(), EInvalidTierConfig);

    assert_tier_prize_counts(tier_prize_counts);
    assert_tier_prize_weights(tier_prize_weights);
}

fun assert_tier_prize_counts(tier_prize_counts: vector<u8>) {
    let length = tier_prize_counts.length();
    let mut i = 0;

    while (i < length) {
        let tier_weight = *tier_prize_counts.borrow(i);
        assert!(tier_weight > 0, EInvalidTierCount);
        i = i + 1;
    };
}

fun assert_tier_prize_weights(tier_prize_weights: vector<u8>) {
    let mut sum :u8 = 0;
    let length = tier_prize_weights.length();
    
    let mut i = 0;
    while (i < length) {
        let tier_weight = *tier_prize_weights.borrow(i);
        assert!(tier_weight > 0, EInvalidTierWeight);
        sum = sum + tier_weight;
        i = i + 1;
    };

    assert!(sum == 100, EInvalidTierWeightsSum);
}
