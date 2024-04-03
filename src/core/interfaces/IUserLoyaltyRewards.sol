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
    function doEmitRewards() external view returns (bool);
    function totalUnclaimedRewards() external view returns (uint256);
    function loyaltyEpochRewardRates(uint256 loyaltyLevel) external view returns (uint256);
    function userRewards(address user) external view returns (uint256);
    function emitUserLoyaltyReward(address user, uint256 epoch, uint256 userLoyaltyLevel, uint256 amountDeposited)
        external;
    function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata userRewardInputs, uint256 ksuTokenPrice) external;

    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata loyaltyEpochRewardRateInput)
        external;

    event LoyaltyRewardsEnabled();
    event LoyaltyRewardsDisabled();
    event UpdatedLoyaltyLevelRewardRate(uint256 indexed loyaltyLevel, uint256 rewardRate);
    event UserLoyaltyRewardsEmitted(address indexed user, uint256 indexed epoch, uint256 rewardAmount);
    event UserRewardClaimed(address indexed user, uint256 rewardAmount);

    error OnlyUserManager();
}
