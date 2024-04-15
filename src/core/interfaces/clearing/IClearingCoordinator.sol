// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";

/**
 * @notice The clearing status of a lending pool for a specific epoch.
 * @custom:member UNINITIALIZED The clearing status is uninitialized.
 * @custom:member STEP1_PENDING The clearing status is pending step 1.
 * @custom:member STEP2_PENDING The clearing status is pending step 2.
 * @custom:member STEP3_PENDING The clearing status is pending step 3.
 * @custom:member STEP4_PENDING The clearing status is pending step 4.
 * @custom:member STEP5_PENDING The clearing status is pending step 5.
 * @custom:member ENDED The clearing status has ended.
 */
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

    function initializeLendingPool(address lendingPool) external;

    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 priorityCalculationBatchSize,
        uint256 acceptRequestsBatchSize,
        ClearingConfiguration calldata clearingConfigOverride,
        bool isConfigOverridden
    ) external;

    /* ========== EVENTS ========== */

    event ClearingExecuted(address indexed lendingPool, uint256 indexed epoch, ClearingStatus clearingStatus);
    event ClearingConfigSet(address indexed lendingPool, uint256 indexed epoch, ClearingConfiguration clearingConfig);

    /* ========== ERRORS ========== */

    error ClearingAlreadyExecuted(uint256 epoch);
    error TargetEpochClearingNotStarted(uint256 targetEpoch);
    error UserLoyaltyLevelsNotYetProcessed(uint256 targetEpoch);
    error InvalidClearingTargetEpochForLendingPool(address lendingPool, uint256 targetEpoch, uint256 nextEpoch);
}
