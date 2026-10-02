// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct EpochUserLoyaltyProcessing {
    bool didStart;
    uint256 userCount;
    uint256 processedUsersCount;
}

interface IUserManager {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function calculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view returns (uint8 loyaltyLevel);
    function epochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory);
    function userLendingPools(address user) external view returns (address[] memory lendingPools);
    function userCount() external view returns (uint256);
    function allUsers() external view returns (address[] memory);
    function userTotalPendingAndActiveDepositedAmount(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount);
    function userTotalPendingAndActiveDepositedAmountForCurrentEpoch(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount);
    function hasUserRKSU(address user) external view returns (bool);
    function canUserDepositInJuniorTranche(address user) external view returns (bool);
    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view returns (bool);
    function userLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint8 loyaltyLevel);
    function userActiveTrancheCount(address user) external view returns (uint256);
    function isUserActiveInTranche(address user, address tranche) external view returns (bool);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external;
    function userRequestedDeposit(address user, address lendingPool) external;
    function addUserActiveTranche(address user, address lendingPool) external;
    function removeUserActiveTranche(address user, address lendingPool) external;
    function syncUserActiveTranche(address user, address lendingPool, address tranche) external;
    function syncUserActiveTrancheFromTranche(address user, address lendingPool, bool isActive) external;
    function syncUserFees(address user) external;
    function updateUserLendingPools(uint256 fromIndex, uint256 toIndex) external;

    /* ========== EVENTS ========== */

    event UserLoyaltyLevelUpdated(address indexed user, uint256 indexed epoch, uint256 loyaltyLevel);
    event UserLoyaltyLevelsForEpochProcessed(uint256 indexed epoch, uint256 userCount);
    /// @notice A user's active flag for a tranche changed. `count` is the user's active tranche count after it.
    event UserActiveTrancheUpdated(
        address indexed user, address indexed lendingPool, address indexed tranche, bool isActive, uint256 count
    );
    /// @notice A tranche reported the user's last shares leaving it, but the (user, tranche) pair was not recorded
    /// as active, so there was nothing to remove.
    /// @dev The removal is skipped, so a clearing never reverts. The user has left this tranche, so this pair needs
    /// no repair. The record was missing before, so the user's count may have been one too low while they held it:
    /// run `syncUserFees(user)` to realign the user's fee eligibility, and `syncUserActiveTranche` on the user's
    /// other tranches if more drift is suspected.
    event RemovalForInactiveTranche(address indexed user, address indexed lendingPool, address indexed tranche);

    /* ========== ERRORS ========== */

    error BadUserIndex();
}
