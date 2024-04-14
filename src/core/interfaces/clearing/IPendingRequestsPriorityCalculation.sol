// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IClearingStepsData.sol";

error PendingRequestsPriorityCalculationIsPending();

interface IPendingRequestsPriorityCalculation {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the status of the pending requests priority calculation task.
     * @param targetEpoch The epoch of pending user request.
     * @return The status of the pending requests priority calculation task.
     */
    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) external view returns (TaskStatus);

    /**
     * @notice Returns the amount of pending user requests remaining to complete the task.
     * @dev
     * This function can be completed in multiple transactions.
     * @param targetEpoch The epoch of pending user request.
     * @return The amount of pending user requests remaining to complete the task.
     */
    function remainingPendingRequestsPriorityCalculation(uint256 targetEpoch) external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

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
    function calculatePendingRequestsPriorityBatch(uint256 batchSize, uint256 targetEpoch) external;

    /* ========== ERRORS ========== */

    /**
     * @dev Indicates task pending requests priority calculation task has already been processed
     * @param targetEpoch The epoch of the pending requests priority calculation task that has been processed
     */
    error PendingRequestsPriorityCalculationAlreadyProcessed(uint256 targetEpoch);

    /**
     * @dev Indicates task pending requests priority calculation task is not completed
     * @param targetEpoch The epoch of the  pending requests priority calculation task that is not completed
     */
    error PendingRequestsPriorityCalculationIsNotCompleted(uint256 targetEpoch);
}
