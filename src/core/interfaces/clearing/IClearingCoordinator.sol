// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

enum ClearingStatus {
    UNINITIALISED,
    STEP1_PENDING,
    STEP2_PENDING,
    STEP3_PENDING,
    STEP4_PENDING,
    STEP5_PENDING,
    ENDED
}

/**
 * @notice The actual configuration that will be applied per lending pool and epoch when clearing.
 * @custom:member clearingConfiguration The actual clearingConfiguration applied.
 * @custom:member isOverwritten true when clearingConfiguration is overwritten, false if not.
 * @custom:member isSet true when clearingConfiguration is set, false if not.
 */
struct AppliedClearingConfiguration {
    ClearingConfiguration config;
    bool isOverwritten;
    bool isSet;
}

interface IClearingCoordinator {
    function lendingPoolClearingStatus(address lendingPool, uint256 epoch)
        external
        view
        returns (ClearingStatus status);
    function isLendingPoolClearingPending(address lendingPool) external view returns (bool isPending);

    function nextLendingPoolClearingEpoch(address lendingPool) external view returns (uint256 nextEpoch);

    /**
     * @notice Initializes the newly created lending pool in the clearing coordinator.
     * @param lendingPool The lending pool address.
     */
    function initializeLendingPool(address lendingPool) external;

    /**
     * @notice Should be called if you need to overwrite the default clearing configuration.
     * @dev
     * Should be optionally called before doClearing. Called once.
     * @param lendingPool The lending pool that clearing config will be registered.
     * @param epoch The epoch to run clearing against.
     * @param clearingConfig The clearing config that will overwrite the default one.
     */
    function overwriteClearingConfig(address lendingPool, uint256 epoch, ClearingConfiguration calldata clearingConfig)
        external;

    /**
     * @notice Removes the clearing config overwrite.
     * @param lendingPool The lending pool that clearing config will be registered.
     * @param epoch The epoch to run clearing against.
     */
    function setDefaultClearingConfig(address lendingPool, uint256 epoch) external;

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
     * @param targetEpoch The epoch of the clearing config.
     * @return clearingConfig The clearing config that will overwrite the default one.
     */
    function getClearingConfig(address lendingPoolAddress, uint256 targetEpoch)
        external
        returns (ClearingConfiguration memory);

    event ClearingExecuted(address lendingPool, uint256 epoch, ClearingStatus clearingStatus);

    error ClearingAlreadyExecuted(uint256 epoch);
    error TargetEpochNotStarted(uint256 targetEpoch, uint256 currentEpoch);
    error TargetEpochClearingNotStarted(uint256 targetEpoch);
    error UserLoyaltyLevelsNotYetProcessed(uint256 targetEpoch);
    error ClearingNotEndedForPreviousEpoch(uint256 previousEpoch);
    error InvalidClearingTargetEpochForLendingPool(address lendingPool, uint256 targetEpoch, uint256 nextEpoch);
    error CannotOverrideClearingConfig(address lendingPool, uint256 epoch);
}
