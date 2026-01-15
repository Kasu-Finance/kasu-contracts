// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./UserManager.sol";
import "./interfaces/IUserManager.sol";

/**
 * @title UserManagerLite
 * @notice Extension of UserManager where loyalty processing is bypassed for Lite deployments.
 */
contract UserManagerLite is UserManager {
    constructor(ISystemVariables systemVariables_, IKSULocking ksuLocking_, IUserLoyaltyRewards userLoyaltyRewards_)
        UserManager(systemVariables_, ksuLocking_, userLoyaltyRewards_)
    {}

    /**
     * @notice Always returns true for loyalty level processed check.
     * @return Always true.
     */
    function areUserEpochLoyaltyLevelProcessed(uint256) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Always returns true for junior tranche deposit check.
     * @return Always true.
     */
    function canUserDepositInJuniorTranche(address) external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Always returns 0 for user loyalty level.
     */
    function calculatedUserEpochLoyaltyLevel(address, uint256) external pure override returns (uint8) {
        return 0;
    }

    /**
     * @notice Always returns a default EpochUserLoyaltyProcessing struct.
     */
    function epochUserLoyaltyProcessing(uint256) external pure override returns (EpochUserLoyaltyProcessing memory) {
        return EpochUserLoyaltyProcessing({didStart: false, userCount: 0, processedUsersCount: 0});
    }

    /**
     * @notice Always returns (currentEpoch, 0) for user loyalty level.
     */
    function userLoyaltyLevel(address) external view override returns (uint256 currentEpoch, uint8 loyaltyLevel) {
        currentEpoch = _systemVariables.currentEpochNumber();
        loyaltyLevel = 0;
    }

    /**
     * @notice No-op for batch loyalty calculation.
     */
    function batchCalculateUserLoyaltyLevels(uint256) external pure override {
        // Loyalty calculation is disabled.
    }
}
