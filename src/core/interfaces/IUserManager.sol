// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IUserManager {
    function getUserLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint256 loyaltyLevel);
    function getUserLendingPools(address user) external returns (address[] memory lendingPools);
    function hasUserRKSU(address user) public view returns (bool);
    function canUserDepositInJuniorTranche(address user) external view returns (bool);

    // EVENTS
    event UserLoyaltyLevelUpdated(address indexed user, uint256 indexed epoch, uint256 loyaltyLevel);
}
