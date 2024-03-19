// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

interface IClearingManager is IPendingRequestsPriorityCalculation, IAcceptedRequestsCalculation {
    function registerClearingConfig(uint256 epoch, ClearingInput calldata clearingConfig) external;

    function doClearing(
        uint256 epoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external;

    function getClearingConfig(uint256 epoch) external returns (ClearingInput memory);
}
