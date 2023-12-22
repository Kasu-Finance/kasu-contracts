// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IUserManager {
    function getUserLoyaltyLevel(address user) external returns (uint256 loyaltyLevel);
    function getUserTotalDepositedAmount(address user)
        external
        returns (uint256 totalDeposit, uint256 activeDeposit, uint256 pendingDeposit);
    function getUserLendingPools(address user) external returns (address[] memory lendingPools);
}
