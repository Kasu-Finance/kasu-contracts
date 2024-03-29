// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IClearingStepsData.sol";

error AcceptedRequestsExecutionAlreadyInitialised(uint256 epoch);
error AcceptedRequestsExecutionAlreadyProcessed(uint256 epoch);

interface IAcceptedRequestsExecution {
    /**
     * @notice Initialises the task and saves all data from previous tasks to run it.
     * @dev
     * Must be called before executeAcceptedRequestsBatch. Called once.
     * @param targetEpoch The epoch to run the task against.
     */
    function init(uint256 targetEpoch) external;

    /**
     * @notice Processes as many userRequests as defined by batchSize. This task accepts user requests, either deposits
     * or withdrawals, by following instructions from previous steps.
     * @dev
     * Can be run in multiple transactions.
     * @param targetEpoch The epoch to run the task against
     * @param batchSize The amount of userRequests that you want to process in this transaction.
     */
    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external;

    /**
     * @notice Returns the status of the accepted requests execution task.
     * @param targetEpoch The epoch of pending user request.
     * @return The status of  the accepted requests execution task.
     */
    function acceptedRequestsExecutionPerEpochStatus(uint256 targetEpoch) external view returns (TaskStatus);
}
