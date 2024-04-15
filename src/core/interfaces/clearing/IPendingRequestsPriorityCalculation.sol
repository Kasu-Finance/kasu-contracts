// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IClearingStepsData.sol";

interface IPendingRequestsPriorityCalculation {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) external view returns (TaskStatus);
    function remainingPendingRequestsPriorityCalculation(uint256 targetEpoch) external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function calculatePendingRequestsPriorityBatch(uint256 targetEpoch, uint256 batchSize) external;

    /* ========== ERRORS ========== */

    /**
     * @notice Indicates task pending requests priority calculation task has already been processed
     * @param targetEpoch The epoch of the pending requests priority calculation task that has been processed
     */
    error PendingRequestsPriorityCalculationAlreadyProcessed(uint256 targetEpoch);
}
