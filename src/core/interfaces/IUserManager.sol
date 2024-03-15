// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct EpochUserLoyaltyProcessing {
    bool didStart;
    uint256 userCount;
    uint256 processedUsersCount;
}

interface IUserManager {
    function getCalculatedUserEpochLoyaltyLevel(address user, uint256 epoch)
        external
        view
        returns (uint256 loyaltyLevel);
    function getEpochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory);
    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view returns (bool);
    function getUserLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint256 loyaltyLevel);
    function getUserLendingPools(address user) external returns (address[] memory lendingPools);
    function hasUserRKSU(address user) external view returns (bool);
    function canUserDepositInJuniorTranche(address user) external view returns (bool);

    // EVENTS
    event UserLoyaltyLevelUpdated(address indexed user, uint256 indexed epoch, uint256 loyaltyLevel);
    event UserLoyaltyLevelsForEpochProcessed(uint256 indexed epoch, uint256 userCount);
}
