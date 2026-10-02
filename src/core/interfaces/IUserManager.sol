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
    function updateUserLendingPools(uint256 fromIndex, uint256 toIndex) external;

    /* ========== EVENTS ========== */

    event UserLoyaltyLevelUpdated(address indexed user, uint256 indexed epoch, uint256 loyaltyLevel);
    event UserLoyaltyLevelsForEpochProcessed(uint256 indexed epoch, uint256 userCount);
    /// @notice A user's active flag for a tranche changed. `count` is the user's active tranche count after it.
    event UserActiveTrancheUpdated(
        address indexed user, address indexed lendingPool, address indexed tranche, bool isActive, uint256 count
    );
    /// @notice A tranche reported a user leaving it while the user was not recorded as active in it.
    /// @dev The removal is skipped so clearing cannot revert; the event surfaces the earlier desync.
    /// Repair: `syncUserActiveTranche(user, lendingPool, tranche)` for each tranche of the user.
    event UserActiveTrancheCountUnderflow(address indexed user, address indexed lendingPool, address indexed tranche);

    /* ========== ERRORS ========== */

    error BadUserIndex();
}
