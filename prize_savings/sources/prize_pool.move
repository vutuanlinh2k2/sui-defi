module prize_savings::prize_pool;

use prize_savings::decimal::{Decimal, div, ceil, from};
use prize_savings::twab_controller::{TwabController}

;
use sui::balance::{Balance};
use sui::bcs;
use sui::hash::{keccak256};

// === Errors ===
// const ENoDrawsAwarded: u64 = 1;
// const EInvalidTierIndexInput: u64 = 2;

// === Structs ===
public struct PrizePool<phantom T> has key {
    id: UID,
    pool_id: ID,
    draw_id: u64,
    prize_per_winner_per_tier: vector<u64>,
    prize_count_per_tier: vector<u8>,
    prize_claimed_per_tier: vector<u8>,
    twab_controller_snapshot: TwabController,
    draw_random_number: u256,
    prize_balances: Balance<T>
}

// === Public View Functions ===
public fun pool_id<T>(self: &PrizePool<T>): ID {
  self.pool_id
}

public fun draw_id<T>(self: &PrizePool<T>): u64 {
  self.draw_id
}

public fun prize_per_winner_per_tier<T>(self: &PrizePool<T>): vector<u64> {
  self.prize_per_winner_per_tier
}

public fun prize_count_per_tier<T>(self: &PrizePool<T>): vector<u8> {
  self.prize_count_per_tier
}

public fun prize_claimed_per_tier<T>(self: &PrizePool<T>): vector<u8> {
  self.prize_claimed_per_tier
}

public fun twab_controller_snapshot<T>(self: &PrizePool<T>): TwabController {
  self.twab_controller_snapshot
}

public fun draw_random_number<T>(self: &PrizePool<T>): u256 {
  self.draw_random_number
}

public fun prize_balances_amount<T>(self: &PrizePool<T>): u64 {
  self.prize_balances.value()
}

// public fun is_winner<T>(self: &PrizePool<T>, user: address, tier: u64, prize_index: u64) {
//   assert!(self.last_awarded_draw_id > 0, ENoDrawsAwarded);

//   let num_of_tiers = self.assert_and_get_num_of_tiers();
//   assert!(tier < num_of_tiers, EInvalidTierIndexInput);

//   let tier_prize_count = self.get_tier_prize_count(prize_index);

//   let pseudo_random_number = calculate_pseudo_random_number(
//     self.last_awarded_draw_id, 
//     self.pool_id, 
//     user, 
//     tier, 
//     prize_index, 
//     self.draw_random_number
//   );

//   /* 
//     1. getting the pool portion from the first to the last draw?
//       - multiple pool that store the the same asset can contribute to a prize pool
//       - to make it simple, skip this for now, assuming 1 pool → 1 prize pool
//     2. getting user twab and vault twab? (is there an easier way for now)
//       - store for each draw 
//       - update every time this change
//         - map (table) each user, for each also
//       - easier way is this: not official until the new draw happen? 
//       - what if they want to withdraw? 
//       - or just check with the current draw? then update the twab for the current draw
//       - currently each prize tiers based on how many draws til we have one

//    */

//   //   (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = getVaultUserBalanceAndTotalSupplyTwab(
//   //     _vault,
//   //     _user,
//   //     startDrawIdInclusive,
//   //     lastAwardedDrawId_
//   //   );

//   //   return
//   //     TierCalculationLib.isWinner(
//   //       userSpecificRandomNumber,
//   //       _userTwab,
//   //       _vaultTwabTotalSupply,
//   //       vaultPortion,
//   //       tierOdds
//   //     );

//   // * assert lastAwardedDrawId is not 0 
//   // * assert tier must me less than numberOfTiers (tiers.length)
//   // * get tier odds (based on tiers and number of tiers) - getTierOdds function
//   // * startDrawIdInclusive = computeRangeStartDrawIdInclusive(lastAwardedDrawId_, TierCalculationLib.estimatePrizeFrequencyInDraws(tierOdds, grandPrizePeriodDraws))
//   // * get tier prize count
//   // * assert prize_index < prize count
//   // * calculatePseudoRandomNumber
//   // * get vault portion (skip)

//       //     (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = getVaultUserBalanceAndTotalSupplyTwab(
// //       _vault,
// //       _user,
// //       startDrawIdInclusive,
// //       lastAwardedDrawId_
// //     );

// //     return
// //       TierCalculationLib.isWinner(
// //         userSpecificRandomNumber,
// //         _userTwab,
// //         _vaultTwabTotalSupply,
// //         vaultPortion,
// //         tierOdds
// //       );
// }

// === Package Functions ===

public(package) fun create_and_share_prize_pool<T>(
  pool_id: ID,
  draw_id: u64,
  prize_count_per_tier: vector<u8>,
  prize_per_winner_per_tier: vector<u64>,
  twab_controller_snapshot: TwabController,
  draw_random_number: u256,
  prize_balances: Balance<T>,
  ctx: &mut TxContext
): ID {
  let num_of_tiers = prize_per_winner_per_tier.length();
  let mut prize_claimed_per_tier = vector::empty<u8>();

  let mut i = 0;
  while (i < num_of_tiers) {
    prize_claimed_per_tier.push_back(0);
    i = i + 1;
  };

  let prize_pool = PrizePool {
    id: object::new(ctx),
    pool_id,
    draw_id,
    prize_count_per_tier,
    prize_per_winner_per_tier,
    prize_claimed_per_tier,
    twab_controller_snapshot,
    draw_random_number,
    prize_balances
  };

  let id = object::id(&prize_pool);
    transfer::share_object(prize_pool);

    id
}

// === Private Functions

// fun get_tier_prize_count<T>(self: &PrizePool<T>, prize_index: u64): u64 {
//   let num_of_tiers = self.assert_and_get_num_of_tiers();
//     assert!(prize_index < num_of_tiers, EInvalidTierIndexInput);
//     *vector::borrow(&self.prize_count_per_tier, prize_index)
// }

// fun assert_and_get_num_of_tiers<T>(self: &PrizePool<T>): u64 {
//     self.assert_tier_structure();
//     self.prize_count_per_tier.length()
// }

// fun assert_tier_structure<T>(self: &PrizePool<T>) {
//   assert!(self.prize_count_per_tier.length() == self.tier_prize_weights.length());
// }

// TODO: write test for this function
/// Calculates a pseudo-random number unique to the inputs
#[allow(unused_function)]
fun calculate_pseudo_random_number(
    draw_id: u64,
    pool_id: ID,
    user: address,
    tier: u64,
    prize_index: u64,
    draw_random_number: u256
): u256 {
    let mut bytes = vector::empty<u8>();

    vector::append(&mut bytes, bcs::to_bytes(&draw_id));
    vector::append(&mut bytes, pool_id.to_bytes());
    vector::append(&mut bytes, user.to_bytes());
    vector::append(&mut bytes, bcs::to_bytes(&tier));
    vector::append(&mut bytes, bcs::to_bytes(&prize_index));
    vector::append(&mut bytes, bcs::to_bytes(&draw_random_number));

    let hash = keccak256(&bytes);
    let mut bcs = bcs::new(hash);
    bcs::peel_u256(&mut bcs)
}

#[allow(unused_function)]
fun estimate_prize_frequency_in_draws(tierOdds: Decimal, grand_prize_period: u64): u64 {
  let prize_frequency_in_draws = ceil(div(from(1_000_000_000), tierOdds));
  if (prize_frequency_in_draws > grand_prize_period) {
    grand_prize_period
  } else {
    prize_frequency_in_draws
  }
}

#[allow(unused_function)]
fun calculate_range_start_draw_id_inclusive(end_draw_id_inclusive: u64, range_size: u64): u64 {
  assert!(range_size > 0);
  if (range_size > end_draw_id_inclusive) {
    1
  } else {
    end_draw_id_inclusive - range_size + 1
  }
}
// function getVaultPortion(
//     address _vault,
//     uint24 _startDrawIdInclusive,
//     uint24 _endDrawIdInclusive
//   ) public view returns (SD59x18) {
//     if (_vault == DONATOR) {
//       return sd(0);
//     }
//     (uint256 vaultContributed, uint256 totalContributed) = _getVaultShares(_vault, _startDrawIdInclusive, _endDrawIdInclusive);
//     if (totalContributed == 0) {
//       return sd(0);
//     }
//     return sd(
//       SafeCast.toInt256(
//         vaultContributed
//       )
//     ).div(sd(SafeCast.toInt256(totalContributed)));
//   }
// function _getVaultShares(
//     address _vault,
//     uint24 _startDrawIdInclusive,
//     uint24 _endDrawIdInclusive
//   ) internal view returns (uint256 shares, uint256 totalSupply) {
//     uint256 totalContributed = _totalAccumulator.getDisbursedBetween(
//       _startDrawIdInclusive,
//       _endDrawIdInclusive
//     );
//     uint256 totalDonated = _vaultAccumulator[DONATOR].getDisbursedBetween(_startDrawIdInclusive, _endDrawIdInclusive);
//     totalSupply = totalContributed - totalDonated;
//     shares = _vaultAccumulator[_vault].getDisbursedBetween(
//       _startDrawIdInclusive,
//       _endDrawIdInclusive
//     );
//   }