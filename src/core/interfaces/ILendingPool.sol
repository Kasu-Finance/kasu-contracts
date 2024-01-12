// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Interface for the LendingPool contract.
 * @dev Can only be called by the LendingPoolManager contract.
 */
interface ILendingPool {
    function requestDeposit(address user, address tranche, uint256 amount) external returns (uint256 dNftID);

    function requestWithdrawal(address user, address tranche, uint256 amount) external returns (uint256 wNftID);

    function cancelDepositRequest(address user, address tranche, uint256 dNftID) external;

    function cancelWithdrawalRequest(address user, address tranche, uint256 wNftID) external;

    function applyYield(uint128 yield) external returns (uint256);
}


// requestDeposit(trench, amount) - pendingDeposit
// pendingDepositAccepted(trench, dNft)
// pendingDepositDeclined(trench, dNft)

// requestWithdrawal(trench, amount) - pendindWithdraw
// pendingWithdarAccepted(trench, wNft)

// repaymentDeposit(amount)
// loanWithdrawal(amount)

// protocolFeesWithdrawal()