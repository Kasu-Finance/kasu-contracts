// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IPendingRequestsPriorityCalculation.sol";

error AcceptedRequestsExecutionAlreadyInitialised(uint256 epoch);
error AcceptedRequestsExecutionAlreadyProcessed(uint256 epoch);

interface IAcceptedRequestsExecution {
    function registerAcceptedRequestExecution(
        uint256 targetEpoch,
        PendingDeposits calldata pendingDeposits,
        PendingWithdrawals calldata pendingWithdrawals,
        uint256[][][] calldata tranchePriorityDepositsAccepted,
        uint256[] calldata acceptedPriorityWithdrawalAmounts
    ) external;

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external;

    /**
     * @notice Returns the status of the accepted requests execution task.
     * @param targetEpoch The epoch of pending user request.
     * @return The status of  the accepted requests execution task.
     */
    function acceptedRequestsExecutionPerEpochStatus(uint256 targetEpoch) external view returns (TaskStatus);
}
