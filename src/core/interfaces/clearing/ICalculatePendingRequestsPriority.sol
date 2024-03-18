// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct PendingDeposits {
    uint256 totalDepositAmount;
    uint256[] trancheDepositsAmounts;
    // array by tranche and priority
    uint256[][] tranchePriorityDepositsAmounts;
}

struct PendingWithdrawals {
    uint256 totalWithdrawalsAmount;
    // array by priority
    uint256[] priorityWithdrawalAmounts;
}

error PendingRequestsPriorityCalculationIsPending();

interface ICalculatePendingRequestsPriority {
    /**
     * @notice Sets priorities for an amount of pending deposits and withdrawals.
     * @dev
     * This function is called by the clearing manager.
     * This task can be completed in multiple transactions.
     * Loops over a set of pending user requests and assigns user's loyalty level as priority.
     * This set contains the pending deposits for the current epoch and all pending withdrawals until this epoch.
     * Pending withdrawals have an extra maximum priority for forced withdrawals and requests open for more than five epochs.
     * @param batchSize The amount of pending user requests that will be processed in one transaction.
     * @param targetEpoch The epoch of pending user request.
     */
    function calculatePendingRequestsPriority(uint256 batchSize, uint256 targetEpoch) external;

    /**
     * @notice Returns the amount of pending user requests remaining to complete the task.
     * @dev
     * This function can be completed in multiple transactions.
     * @param targetEpoch The epoch of pending user request.
     * @return The amount of pending user requests remaining to complete the task.
     */
    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) external view returns (uint256);

    /**
     * @notice Returns pending deposit grouped by tranche and priority.
     * @param targetEpoch The epoch of pending user request.
     * @return Pending deposit grouped by tranche and priority.
     */
    function getPendingDeposits(uint256 targetEpoch) external view returns (PendingDeposits memory);

    /**
     * @notice Returns pending withdrawals grouped by priority.
     * @param targetEpoch The epoch of pending user request.
     * @return Pending withdrawals grouped by priority.
     */
    function getPendingWithdrawals(uint256 targetEpoch) external view returns (PendingWithdrawals memory);
}
