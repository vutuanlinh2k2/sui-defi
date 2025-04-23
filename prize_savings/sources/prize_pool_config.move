module prize_savings::prize_pool_config;

// === Errors ===
const EInvalidFrequency: u64 = 1;
const EEmptyTiers: u64 = 2;
const EInvalidTierConfig: u64 = 3;
const EInvalidTierWeight: u64 = 4;
const EInvalidTierWeightsSum: u64 = 5;
const EInvalidTierCount: u64 = 6;
const EInvalidExpiryTimeframe: u64 = 7;
const EInvalidTierFrequencyWeights: u64 = 8;

// === Structs ===
public struct PrizePoolConfig has store, copy {
    prize_frequency_days: u8, // Eg. new pool_prize will be created once every 7 days
    expire_timeframe_days: u8, // Eg. number of days before the prize being expired
    prize_count_per_tier: vector<u8>,
    weight_per_tier: vector<u8>,
    // The better the tier, the less frequent it occurs. Eg. Tier 0 must be harder than Tier 1
    // Eg. [10, 7, 4, 1]
    tier_frequency_weights: vector<u8>,
}

// === Public View Functions ===
public fun prize_frequency_days(self: &PrizePoolConfig): u8 {
    self.prize_frequency_days
}

public fun expire_timeframe_days(self: &PrizePoolConfig): u8 {
    self.expire_timeframe_days
}

public fun prize_count_per_tier(self: &PrizePoolConfig): vector<u8> {
    self.prize_count_per_tier
}

public fun weight_per_tier(self: &PrizePoolConfig): vector<u8> {
    self.weight_per_tier
}

public fun tier_frequency_weights(self: &PrizePoolConfig): vector<u8> {
    self.tier_frequency_weights
}

// === Package Functions ===

public(package) fun create_pool_prize_config(
    prize_frequency_days: u8,
    prize_count_per_tier: vector<u8>,
    weight_per_tier: vector<u8>,
    tier_frequency_weights: vector<u8>,
    expire_timeframe_days: u8,
): PrizePoolConfig {
    let config = PrizePoolConfig {
        prize_frequency_days,
        prize_count_per_tier,
        weight_per_tier,
        tier_frequency_weights,
        expire_timeframe_days
    };

    assert_config(&config);

    config
}

// === Private Functions ===

fun assert_config(self: &PrizePoolConfig) {
    let prize_frequency_days = self.prize_frequency_days;
    let prize_count_per_tier = self.prize_count_per_tier;
    let weight_per_tier = self.weight_per_tier;
    let expire_timeframe_days = self.expire_timeframe_days;
    let tier_frequency_weights = self.tier_frequency_weights;

    assert!(prize_frequency_days > 0, EInvalidFrequency);
    assert!(expire_timeframe_days > 0, EInvalidExpiryTimeframe);
    assert!(
        prize_count_per_tier.length() > 0 && 
        weight_per_tier.length() > 0 && 
        tier_frequency_weights.length() > 0, 
        EEmptyTiers
    );
    assert!(prize_count_per_tier.length() == weight_per_tier.length(), EInvalidTierConfig);
    assert!(prize_count_per_tier.length() == tier_frequency_weights.length(), EInvalidTierConfig);

    assert_prize_count_per_tier(prize_count_per_tier);
    assert_weight_per_tier(weight_per_tier);
    assert_tier_frequency_weights(tier_frequency_weights);
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

fun assert_tier_frequency_weights(tier_frequency_weights: vector<u8>) {
    let length = tier_frequency_weights.length();

    let mut i = 0;
    while (i < length - 1) {
        let weight = *tier_frequency_weights.borrow(i);
        let weight_next = *tier_frequency_weights.borrow(i + 1);
        assert!(weight > 1, EInvalidTierFrequencyWeights);
        assert!(weight > weight_next, EInvalidTierFrequencyWeights);

        i = i + 1;
    };

    // Last Item must have no weight (1x)
    assert!(tier_frequency_weights.borrow(length - 1) == 1, EInvalidTierFrequencyWeights);
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

    let mut tier_frequency_weights = vector::empty<u8>();
    tier_frequency_weights.push_back(10);
    tier_frequency_weights.push_back(5);
    tier_frequency_weights.push_back(1);

    let prize_pool_config = PrizePoolConfig {
        prize_frequency_days: 1,
        expire_timeframe_days: 1,
        prize_count_per_tier,
        weight_per_tier,
        tier_frequency_weights
    }; 

    prize_pool_config.assert_config();

    prize_pool_config
}
