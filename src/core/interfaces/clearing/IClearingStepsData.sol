// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Task status.
 * @custom:member UNINITIALIZED The task is uninitialized.
 * @custom:member PENDING The task is pending.
 * @custom:member ENDED The task has ended.
 */
enum TaskStatus {
    UNINITIALIZED,
    PENDING,
    ENDED
}

/**
 * @notice Pending deposit amounts for the clearing target epoch.
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
 * @notice Pending withdrawal amounts for the clearing target epoch.
 * @custom:member totalWithdrawalsAmount Total withdrawal amount.
 * @custom:member priorityWithdrawalAmounts Withdrawal amounts for each priority.
 */
struct PendingWithdrawals {
    uint256 totalWithdrawalsAmount;
    uint256[] priorityWithdrawalAmounts;
}

/**
 * @notice Clearing data used for the lending pool clearing for target epoch.
 * @custom:member pendingDeposits Pending deposit amounts.
 * @custom:member pendingWithdrawals Pending withdrawals amounts.
 * @custom:member tranchePriorityDepositsAccepted Accepted deposit amounts to each tranche for each tranche and priority.
 * @custom:member acceptedPriorityWithdrawalAmounts Accepted withdrawal amounts for each priority.
 * @custom:member totalPendingRequestsToProcess Total pending requests to process for the clearing target epoch.
 */
struct ClearingData {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    uint256[][][] tranchePriorityDepositsAccepted;
    uint256[] acceptedPriorityWithdrawalAmounts;
    uint256 totalPendingRequestsToProcess;
}

/**
 * @notice Lending pool clearing configuration for the target epoch.
 * @custom:member drawAmount Desired draw amount for the current clearing.
 * @custom:member trancheDesiredRatios Lending pool tranche desired ratios in percentages.
 * @custom:member maxExcessPercentage Maximum excess balance percentage.
 * @custom:member minExcessPercentage Minimum excess balance percentage.
 */
struct ClearingConfiguration {
    uint256 drawAmount;
    uint256[] trancheDesiredRatios;
    uint256 maxExcessPercentage;
    uint256 minExcessPercentage;
}
