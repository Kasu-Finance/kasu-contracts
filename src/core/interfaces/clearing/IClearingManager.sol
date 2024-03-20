// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

interface IClearingManager is IPendingRequestsPriorityCalculation, IAcceptedRequestsCalculation {
    function registerClearingConfig(uint256 epoch, ClearingConfiguration calldata clearingConfig) external;

    function doClearing(
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external;

    function getClearingConfig(uint256 epoch) external view returns (ClearingConfiguration memory);
}
