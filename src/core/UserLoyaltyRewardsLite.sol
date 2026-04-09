// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IUserLoyaltyRewards.sol";

/**
 * @title UserLoyaltyRewardsLite
 * @notice Lite implementation that disables loyalty rewards.
 */
contract UserLoyaltyRewardsLite is IUserLoyaltyRewards {
    function doEmitRewards() external pure override returns (bool) {
        return false;
    }

    function totalUnclaimedRewards() external pure override returns (uint256) {
        return 0;
    }

    function loyaltyEpochRewardRates(uint256) external pure override returns (uint256) {
        return 0;
    }

    function userRewards(address) external pure override returns (uint256) {
        return 0;
    }

    function emitUserLoyaltyReward(address, uint256, uint256, uint256) external pure override {}
    function setDoEmitRewards(bool) external pure override {}
    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata) external pure override {}
    function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata, uint256) external pure override {}
    function claimReward(uint256) external pure override {}
}
