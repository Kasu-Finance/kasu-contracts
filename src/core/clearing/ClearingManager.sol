// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearingManager.sol";
import "./PendingRequestsPriorityCalculation.sol";
import "./AcceptedRequestsCalculation.sol";

abstract contract ClearingManager is
    IClearingManager,
    PendingRequestsPriorityCalculation,
    AcceptedRequestsCalculation
{
    mapping(uint256 => ClearingInput) private clearingConfigPerEpoch;

    function registerClearingConfig(uint256 epoch, ClearingInput calldata clearingConfig) external {
        clearingConfigPerEpoch[epoch] = clearingConfig;
    }

    function doClearing(
        uint256 epoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external {
        if (pendingRequestsPriorityCalculationStatus(epoch) != PendingRequestsTaskStatus.ENDED) {
            calculatePendingRequestsPriority(pendingRequestsPriorityCalculationBatchSize, epoch);
        }
    }

    function getClearingConfig(uint256 epoch) external returns (ClearingInput memory) {
        return clearingConfigPerEpoch[epoch];
    }
}
