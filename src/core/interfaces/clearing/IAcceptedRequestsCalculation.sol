// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Clearing calculation input.
 * @custom:member config Clearing configuration.
 * @custom:member balance Lending pool balances.
 * @custom:member pendingDeposits Pending deposits.
 * @custom:member pendingWithdrawals Pending withdrawals.
 */
struct ClearingInput {
    ClearingConfiguration config;
    LendingPoolBalance balance;
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
}

/**
 * @notice Clearing configuration.
 * @custom:member borrowAmount Desired borrow amount for current clearing.
 * @custom:member trancheDesiredRatios Lending pool ranche desired ratios in percentages.
 * @custom:member maxExcessPercentage Maximum excess balance percentage.
 * @custom:member minExcessPercentage Minimum excess balance percentage.
 */
struct ClearingConfiguration {
    uint256 borrowAmount;
    uint256[] trancheDesiredRatios;
    uint256 maxExcessPercentage;
    uint256 minExcessPercentage;
}

/**
 * @notice Lending pool balances.
 * @custom:member excess Lending pool excess balance. Lending pool available assets.
 * @custom:member owed Owed balance.
 */
struct LendingPoolBalance {
    uint256 excess;
    uint256 owed;
}

/**
 * @notice Pending deposits.
 * @custom:member totalDepositAmount Total deposit amount.
 * @custom:member trancheDepositsAmounts Deposit amounts for each tranche.
 * @custom:member tranchePriorityDepositsAmounts Deposit amounts for each tranche and priority.
 */
struct PendingDeposits {
    uint256 totalDepositAmount;
    uint256[] trancheDepositsAmounts;
    uint256[][] tranchePriorityDepositsAmounts;
}

/**
 * @notice Pending withdrawals.
 * @custom:member totalWithdrawalsAmount Total withdrawal amount.
 * @custom:member priorityWithdrawalAmounts Withdrawal amounts for each priority.
 */
struct PendingWithdrawals {
    uint256 totalWithdrawalsAmount;
    uint256[] priorityWithdrawalAmounts;
}

interface IAcceptedRequestsCalculation {
    function calculateAcceptedRequests(ClearingInput calldata input)
        external
        view
        returns (
            uint256[][][] memory tranchePriorityDepositsAccepted,
            uint256[] memory acceptedPriorityWithdrawalAmounts
        );

    error BorrowAmountExceedsAvailable(uint256 desiredBorrowAmount, uint256 maximumAvailableToBorrow);
    error InvalidDepositResult();
    error InvalidWithdrawalResult();
    error InvalidResult();
}
