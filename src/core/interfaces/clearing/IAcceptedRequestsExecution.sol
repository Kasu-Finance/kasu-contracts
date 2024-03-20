// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IPendingRequestsPriorityCalculation.sol";

error AcceptedRequestsExecutionAlreadyInitialised(uint256 epoch);
error AcceptedRequestsExecutionAlreadyProcessed(uint256 epoch);

interface IAcceptedRequestsExecution {
    function registerAcceptedRequestExecution(
        uint256 targetEpoch,
        PendingDeposits memory pendingDeposits,
        PendingWithdrawals memory pendingWithdrawals,
        uint256[][][] memory tranchePriorityDepositsAccepted,
        uint256[] memory acceptedPriorityWithdrawalAmounts
    ) external;

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external;
}
