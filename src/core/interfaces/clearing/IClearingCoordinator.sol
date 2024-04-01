// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

interface IClearingCoordinator {
    /**
     * @notice Should be called if you need to overwrite the default clearing configuration.
     * @dev
     * Should be optionally called before doClearing. Called once.
     * @param lendingPool The lending pool that clearing config will be registered.
     * @param epoch The epoch to run clearing against.
     * @param clearingConfig The clearing config that will overwrite the default one.
     */
    function registerClearingConfig(address lendingPool, uint256 epoch, ClearingConfiguration calldata clearingConfig)
        external;

    /**
     * @notice Runs all the tasks required for clearing to succeed. Tasks run in sequence.
     * @dev
     * This task can be completed in multiple transactions.
     * @param lendingPoolAddress The lending pool that clearing config will be registered.
     * @param targetEpoch The epoch to run clearing against.
     * @param pendingRequestsPriorityCalculationBatchSize The amount of user requests that `pending requests priority
     * calculation` will process in one transaction.
     * @param acceptedRequestsExecutionBatchSize The amount of user requests that `accepted requests execution` task
     * will process in one transaction.
     */
    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external;

    /**
     * @notice Returns the active config for the clearing task.
     * @param lendingPoolAddress The lending pool of the clearing config.
     * @param epoch The epoch of the clearing config.
     * @return clearingConfig The clearing config that will overwrite the default one.
     */
    function getClearingConfig(address lendingPoolAddress, uint256 epoch)
        external
        view
        returns (ClearingConfiguration memory);

    error ClearingAlreadyExecuted(uint256 epoch);
}
