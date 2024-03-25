// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

enum TaskStatus {
    UNINITIALISED,
    PENDING,
    ENDED
}

interface IClearingManager {
    function registerClearingConfig(address lendingPool, uint256 epoch, ClearingConfiguration calldata clearingConfig)
        external;

    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external;

    function getClearingConfig(address lendingPoolAddress, uint256 epoch)
        external
        view
        returns (ClearingConfiguration memory);

    error ClearingAlreadyExecuted(uint256 epoch);
}
