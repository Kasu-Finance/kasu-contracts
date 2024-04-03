// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct LoyaltyEpochRewardRateInput {
    uint256 loyaltyLevel;
    uint256 epochRewardRate;
}

interface IUserLoyaltyRewards {
    function emitUserLoyaltyReward(address user, uint256 epoch, uint256 userLoyaltyLevel, uint256 amountDeposited)
        external;
    function emitUserLoyaltyRewardManually(
        address user,
        uint256 epoch,
        uint256 userLoyaltyLevel,
        uint256 amountDeposited,
        uint256 ksuTokenPrice
    ) external;

    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata loyaltyEpochRewardRateInput)
        external;

    event LoyaltyRewardsEnabled();
    event LoyaltyRewardsDisabled();
    event UpdatedLoyaltyLevelRewardRate(uint256 indexed loyaltyLevel, uint256 rewardRate);
    event UserLoyaltyRewardsEmitted(address indexed user, uint256 indexed epoch, uint256 rewardAmount);
    event UserRewardClaimed(address indexed user, uint256 rewardAmount);

    error OnlyUserManager();
}
