// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

enum TaskStatus {
    UNINITIALISED,
    PENDING,
    ENDED
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

struct ClearingData {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    uint256[][][] tranchePriorityDepositsAccepted;
    uint256[] acceptedPriorityWithdrawalAmounts;
    uint256 totalPendingRequestsToProcess;
}

/**
 * @notice Clearing configuration.
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
    bool isOverridden;
}
