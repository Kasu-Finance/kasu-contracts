// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface ILendingPoolManager {
    function registerPool(address lendingPool) external returns (uint256 poolID);

    /**
     * @dev Users
     */
    function requestDeposit(address lendingPool, address tranche, uint256 amount) external returns (uint256 dNftID);

    /**
     * @dev Users
     */
    function requestWithdrawal(address lendingPool, address tranche, uint256 amount) external returns (uint256 wNftID);

    function cancelDepositRequest(address lendingPool, address tranche, uint256 dNftID) external;

    function cancelWithdrawalRequest(address lendingPool, address tranche, uint256 wNftID) external;

    /**
     * @dev Financing loans
     */
    function repayFunds(address lendingPool, uint256 amount) external returns (uint256 nftID);

    /**
     * @dev Financing loans
     */
    function borrowFunds(address lendingPool, uint256 amount) external returns (uint256 nftID);

    function applyYield(address lendingPool, uint256 amount) external returns (uint256);
}
