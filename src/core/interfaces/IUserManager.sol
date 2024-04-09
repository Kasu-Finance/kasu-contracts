// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct EpochUserLoyaltyProcessing {
    bool didStart;
    uint256 userCount;
    uint256 processedUsersCount;
}

interface IUserManager {
    function userTotalPendingAndActiveDepositedAmount(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount);
    function userTotalPendingAndActiveDepositedAmountForCurrentEpoch(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount);
    function calculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view returns (uint8 loyaltyLevel);
    function epochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory);
    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view returns (bool);
    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external;
    function userLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint8 loyaltyLevel);
    function allUsers() external view returns (address[] memory);
    function userLendingPools(address user) external returns (address[] memory lendingPools);
    function hasUserRKSU(address user) external view returns (bool);
    function canUserDepositInJuniorTranche(address user) external view returns (bool);
    function userRequestedDeposit(address user, address lendingPool) external;
    function updateUserLendingPools(uint256 fromIndex, uint256 toIndex) external;

    // EVENTS
    event UserLoyaltyLevelUpdated(address indexed user, uint256 indexed epoch, uint256 loyaltyLevel);
    event UserLoyaltyLevelsForEpochProcessed(uint256 indexed epoch, uint256 userCount);

    // ERRORS
    error BadUserIndex();
}
