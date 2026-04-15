// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct LoyaltyEpochRewardRateInput {
    uint256 loyaltyLevel;
    uint256 epochRewardRate;
}

struct UserRewardInput {
    address user;
    uint256 epoch;
    uint256 userLoyaltyLevel;
    uint256 amountDeposited;
}

interface IUserLoyaltyRewards {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function doEmitRewards() external view returns (bool);
    function totalUnclaimedRewards() external view returns (uint256);
    function loyaltyEpochRewardRates(uint256 loyaltyLevel) external view returns (uint256);
    function userRewards(address user) external view returns (uint256);
    function maxRewardPerUserPerBatch() external view returns (uint256);
    function maxBatchTotalReward() external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function emitUserLoyaltyReward(address user, uint256 epoch, uint256 userLoyaltyLevel, uint256 amountDeposited)
        external;
    function setDoEmitRewards(bool doEmitRewards_) external;
    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata loyaltyEpochRewardRateInput) external;
    function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata userRewardInputs, uint256 ksuTokenPrice) external;
    function setRewardCaps(uint256 perUser, uint256 perBatch) external;
    function claimReward(uint256 amount) external;

    /* ========== EVENTS ========== */

    event LoyaltyRewardsEnabled();
    event LoyaltyRewardsDisabled();
    event UpdatedLoyaltyLevelRewardRate(uint256 indexed loyaltyLevel, uint256 rewardRate);
    event UserLoyaltyRewardsEmitted(address indexed user, uint256 indexed epoch, uint256 rewardAmount);
    event UserRewardClaimed(address indexed user, uint256 rewardAmount);
    event RewardCapsUpdated(uint256 maxRewardPerUserPerBatch, uint256 maxBatchTotalReward);

    /* ========== ERRORS ========== */

    error OnlyUserManager();
    error RewardCapsNotSet();
    error PerUserCapExceeded(address user, uint256 ksuReward, uint256 cap);
    error BatchCapExceeded(uint256 batchTotal, uint256 cap);
}
