// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

enum ClearingStatus {
    UNINITIALIZED,
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
    bool isOverridden;
    bool isSet;
}

interface IClearingCoordinator {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function lendingPoolClearingStatus(address lendingPool, uint256 epoch)
        external
        view
        returns (ClearingStatus status);

    function isLendingPoolClearingPending(address lendingPool) external view returns (bool isPending);

    function getLendingPoolMaxDrawAmount(address lendingPool) external view returns (uint256 maxDrawAmount);

    function nextLendingPoolClearingEpoch(address lendingPool) external view returns (uint256 nextEpoch);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Initializes the newly created lending pool in the clearing coordinator.
     * @param lendingPool The lending pool address.
     */
    function initializeLendingPool(address lendingPool) external;

    /**
     * @notice Runs all the tasks required for clearing to succeed. Tasks run in sequence.
     * @dev
     * This task can be completed in multiple transactions.
     * @param lendingPoolAddress The lending pool that clearing config will be registered.
     * @param targetEpoch The epoch to run clearing against.
     * @param priorityCalculationBatchSize The amount of user requests that `pending requests priority
     * calculation` will process in one transaction.
     * @param acceptRequestsBatchSize The amount of user requests that `accepted requests execution` task
     * will process in one transaction.
     * @param clearingConfigOverride The config that will be overridden at step3 if isConfigOverridden is true
     * @param isConfigOverridden Determines whether the clearingConfigOverride will be applied instead of default one
     */
    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 priorityCalculationBatchSize,
        uint256 acceptRequestsBatchSize,
        ClearingConfiguration calldata clearingConfigOverride,
        bool isConfigOverridden
    ) external;

    /* ========== ERRORS ========== */

    event ClearingExecuted(address indexed lendingPool, uint256 indexed epoch, ClearingStatus clearingStatus);
    event ClearingConfigSet(address indexed lendingPool, uint256 indexed epoch, ClearingConfiguration clearingConfig);

    error ClearingAlreadyExecuted(uint256 epoch);
    error TargetEpochNotStarted(uint256 targetEpoch, uint256 currentEpoch);
    error TargetEpochClearingNotStarted(uint256 targetEpoch);
    error UserLoyaltyLevelsNotYetProcessed(uint256 targetEpoch);
    error ClearingNotEndedForPreviousEpoch(uint256 previousEpoch);
    error InvalidClearingTargetEpochForLendingPool(address lendingPool, uint256 targetEpoch, uint256 nextEpoch);
    error CannotOverrideClearingConfig(address lendingPool, uint256 epoch);
}
