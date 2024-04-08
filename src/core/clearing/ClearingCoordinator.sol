// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearingCoordinator.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "../interfaces/ISystemVariables.sol";
import "../interfaces/IUserManager.sol";
import "../lendingPool/LendingPoolHelpers.sol";
import "../interfaces/clearing/IClearingSteps.sol";
import "../../shared/AddressLib.sol";

/**
 * @title ClearingCoordinator contract
 * @notice Contract responsible for coordinating clearing process for all lending pools.
 * @dev Clearing process is divided into 5 steps:
 * 1. Apply lending pool interests for the target epoch.
 * 2. Calculate pending deposit and withdrawal request priorities.
 * 3. Calculate accepted deposit and withdrawal amounts for each tranche and priority.
 * 4. Process accepted deposit and accepted withdrawal requests.
 * 5. Draw funds.
 * Clearing is executed for each lending pool separately.
 * Clearing process for a lending pool is executed by calling doClearing function.
 * Clearing must be executed once per epoch for each lending pool to ensure a seamless process.
 * Clearing epochs must be executed in order.
 * User loyalty levels must be processed before proceeding to process user requests (step 2 to 5).
 * Clearing can be executed in multiple transactions by specifying batch sizes for step 2 and step 4.
 * If clearing us not fully processed, clearing can be pending for step 2 or for step 4.
 * Steps 1, 3, and 5 are executed automatically after step 2 or step 4 are completed.
 * Step 1 is executed right when doClearing function is called.
 * Step 2 is executed and processes the amount of user requests specified in the batch size.
 *   If not all user requests are processed, clearing is pending for step 2 until all user requests are processed.
 * Step 3 is executed automatically after step 2 is finished.
 * Step 4 is executed and processes the amount of user requests specified in the batch size.
 *   If not all user requests are processed, clearing is pending for step 4 until all user requests are processed.
 * Step 5 is executed automatically after step 4 is finished.
 * After step 5 is finished, clearing for the target epoch is ended.
 * If clearing for the epoch is executed only after the clearing period, only yield will be applied (step 1) and no user requests will be processed.
 * If clearing is pending for step 2 and the clearing period is over, clearing will be ended and no user requests will be processed.
 * If clearing is pending for step 4 and the clearing period is over, clearing must be fully processed before proceeding to the next epoch clearing.
 * Some lending pool functions are disabled (cancel deposit, cancel withdrawal, force immediate withdrawal) if clearing for the lending pool is pending.
 * Clearing configuration is taken from the lending pool, but can also be overriden for each lending pool and epoch before execution of step 2.
 * If the desired draw amount is more than available funds to draw, the clearing transaction will revert in step 3.
 *   In this case the clearing configuration mush be overriden (to set the valid draw amount) to proceed with the clearing and draw funds.
 */
contract ClearingCoordinator is IClearingCoordinator, LendingPoolHelpers {
    ISystemVariables public immutable systemVariables;
    IUserManager public immutable userManager;

    /// @notice Returns the next clearing epoch that needs to be processed for the lending pool.
    mapping(address lendingPool => uint256 nextClearingEpoch) public nextLendingPoolClearingEpoch;
    /// @notice Returns the status of the clearing process for the lending pool and epoch.
    mapping(address lendingPool => mapping(uint256 epoch => ClearingStatus)) public lendingPoolClearingStatus;
    /// @notice Returns the used clearing configuration for the lending pool and epoch.
    mapping(address lendingPool => mapping(uint256 epoch => AppliedClearingConfiguration)) public
        clearingConfigPerLendingPoolAndEpoch;

    /**
     * @notice Constructor.
     * @param systemVariables_ System variables contract.
     * @param userManager_ User manager contract.
     * @param lendingPoolManager_ Lending pool manager contract.
     */
    constructor(ISystemVariables systemVariables_, IUserManager userManager_, ILendingPoolManager lendingPoolManager_)
        LendingPoolHelpers(lendingPoolManager_)
    {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(address(userManager_));

        systemVariables = systemVariables_;
        userManager = userManager_;
    }

    /**
     * @notice Initializes the clearing process for the lending pool.
     * @dev This function must be called after the lending pool is created.
     */
    function initializeLendingPool(address lendingPool) external onlyLendingPoolManager {
        AddressLib.checkIfZero(lendingPool);

        // sets the next clearing epoch to the current request epoch (if clearing period is active the next epoch is applied)
        nextLendingPoolClearingEpoch[lendingPool] = systemVariables.getCurrentRequestEpoch();
    }

    /**
     * @notice Returns true if clearing for the lending pool is pending.
     * @dev Clearing is pending if previous epoch clearing is not yet ended or if current clearing is not yet ended and it's clearing time.
     * @param lendingPool Lending pool address.
     * @return isPending True if clearing is pending for the lending pool.
     */
    function isLendingPoolClearingPending(address lendingPool) external view returns (bool isPending) {
        uint256 nextTargetEpoch = nextLendingPoolClearingEpoch[lendingPool];
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        if (nextTargetEpoch < currentEpoch) {
            // is pending if previous epoch clearing is not yet ended
            isPending = true;
        } else if (nextTargetEpoch == currentEpoch) {
            if (systemVariables.isClearingTime()) {
                if (lendingPoolClearingStatus[lendingPool][nextTargetEpoch] != ClearingStatus.ENDED) {
                    // is pending if current clearing is not yet ended and it's clearing time
                    isPending = true;
                }
            }
        }
    }

    /**
     * @notice Executes the clearing process for the lending pool.
     * @dev Can be called multiple times to execute clearing in multiple transactions.
     * @param lendingPool Lending pool address.
     * @param targetEpoch Target epoch to execute clearing.
     * @param priorityCalculationBatchSize Numbers of user requests to process in step 2. Only used when step 2 is being processed.
     * @param acceptRequestsBatchSize Numbers of user requests to process in step 4. Only used when step 4 is being processed.
     * @param clearingConfig Clearing configuration to override the lending pool configuration. Is only used when step 3 is processed if `isConfigOverridden` is true.
     * @param isConfigOverridden True if clearing configuration is overridden.
     */
    function doClearing(
        address lendingPool,
        uint256 targetEpoch,
        uint256 priorityCalculationBatchSize,
        uint256 acceptRequestsBatchSize,
        ClearingConfiguration calldata clearingConfig,
        bool isConfigOverridden
    ) external onlyLendingPoolManager {
        ClearingStatus clearingStatus = lendingPoolClearingStatus[lendingPool][targetEpoch];

        if (clearingStatus == ClearingStatus.ENDED) {
            revert ClearingAlreadyExecuted(targetEpoch);
        }

        // check if target epoch for lending pool clearing is valid
        if (clearingStatus == ClearingStatus.UNINITIALISED) {
            if (nextLendingPoolClearingEpoch[lendingPool] != targetEpoch) {
                revert InvalidClearingTargetEpochForLendingPool(
                    lendingPool, targetEpoch, nextLendingPoolClearingEpoch[lendingPool]
                );
            }
        }

        // check if the clearing for the target epoch is started and if clearing period is already over for the target epoch
        bool isPastClearingTime;
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();
        if (targetEpoch == currentEpoch) {
            if (!systemVariables.isClearingTime()) {
                revert TargetEpochClearingNotStarted(targetEpoch);
            }
        } else {
            isPastClearingTime = true;
        }

        // start clearing process for the lending pool
        if (clearingStatus == ClearingStatus.UNINITIALISED) {
            clearingStatus = ClearingStatus.STEP1_PENDING;
        }

        // Step 1 - Apply interests to the lending pool tranches for the target epoch
        if (clearingStatus == ClearingStatus.STEP1_PENDING) {
            ILendingPool(lendingPool).applyInterests(targetEpoch);

            if (isPastClearingTime) {
                // if clearing is run after epoch end, end clearing for target epoch
                clearingStatus = ClearingStatus.ENDED;
            } else {
                // if clearing is run before epoch end, check if user loyalty levels are already processed before proceeding
                bool areUserLoyaltyLevelsProcessed = userManager.areUserEpochLoyaltyLevelProcessed(targetEpoch);

                if (!areUserLoyaltyLevelsProcessed) {
                    revert UserLoyaltyLevelsNotYetProcessed(targetEpoch);
                }

                clearingStatus = ClearingStatus.STEP2_PENDING;
            }
        }

        IClearingSteps _clearingSteps = IClearingSteps(ILendingPool(lendingPool).getPendingPool());

        // Step 2 - Calculate pending deposit and withdrawal request priorities
        if (clearingStatus == ClearingStatus.STEP2_PENDING) {
            // if clearing step 1 is run after epoch end, end clearing for target epoch
            if (isPastClearingTime) {
                clearingStatus = ClearingStatus.ENDED;
            } else {
                _clearingSteps.calculatePendingRequestsPriorityBatch(priorityCalculationBatchSize, targetEpoch);

                if (_clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED) {
                    clearingStatus = ClearingStatus.STEP3_PENDING;
                }
            }
        }

        // Step 3 - Calculate accepted deposit and withdrawal amount for each tranche and priority
        if (clearingStatus == ClearingStatus.STEP3_PENDING) {
            if (isConfigOverridden) {
                // override clearing configuration details
                _overrideClearingConfig(lendingPool, targetEpoch, clearingConfig);
            } else {
                // set the cleating configuration details from the lending pool
                _setDefaultClearingConfig(lendingPool, targetEpoch);
            }

            _clearingSteps.calculateAndSaveAcceptedRequests(
                getClearingConfig(lendingPool, targetEpoch), _getLendingPoolBalance(lendingPool), targetEpoch
            );

            clearingStatus = ClearingStatus.STEP4_PENDING;
        }

        // Step 4 - Process accepted deposit and accepted withdrawal requests
        if (clearingStatus == ClearingStatus.STEP4_PENDING) {
            _clearingSteps.executeAcceptedRequestsBatch(targetEpoch, acceptRequestsBatchSize);

            if (_clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.ENDED) {
                clearingStatus = ClearingStatus.STEP5_PENDING;
            }
        }

        // Step 5 - Draw funds
        if (clearingStatus == ClearingStatus.STEP5_PENDING) {
            if (clearingConfigPerLendingPoolAndEpoch[lendingPool][targetEpoch].config.drawAmount > 0) {
                ILendingPool(lendingPool).drawFunds(
                    clearingConfigPerLendingPoolAndEpoch[lendingPool][targetEpoch].config.drawAmount
                );
            }

            clearingStatus = ClearingStatus.ENDED;
        }

        lendingPoolClearingStatus[lendingPool][targetEpoch] = clearingStatus;

        if (clearingStatus == ClearingStatus.ENDED) {
            nextLendingPoolClearingEpoch[lendingPool] = targetEpoch + 1;
        }

        // emit clearing was executed and at which step it ended
        emit ClearingExecuted(lendingPool, targetEpoch, clearingStatus);
    }

    /**
     * @notice Returns the applied clearing configuration for the lending pool and epoch.
     * @param lendingPool Lending pool address.
     * @param epoch Target epoch.
     * @return clearingConfig Applied clearing configuration.
     */
    function getClearingConfig(address lendingPool, uint256 epoch) public view returns (ClearingConfiguration memory) {
        return clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config;
    }

    //*** Helper Methods ***/

    function _overrideClearingConfig(
        address lendingPool,
        uint256 targetEpoch,
        ClearingConfiguration calldata clearingConfig
    ) internal onlyLendingPoolManager {
        if (nextLendingPoolClearingEpoch[lendingPool] != targetEpoch) {
            revert InvalidClearingTargetEpochForLendingPool(
                lendingPool, targetEpoch, nextLendingPoolClearingEpoch[lendingPool]
            );
        }

        if (lendingPoolClearingStatus[lendingPool][targetEpoch] > ClearingStatus.STEP3_PENDING) {
            revert CannotOverrideClearingConfig(lendingPool, targetEpoch);
        }

        _setClearingConfig(lendingPool, targetEpoch, clearingConfig, true);
    }

    function _setDefaultClearingConfig(address lendingPool, uint256 epoch) private {
        ClearingConfiguration memory clearingConfiguration = _getLendingPoolClearingConfig(lendingPool);
        _setClearingConfig(lendingPool, epoch, clearingConfiguration, false);
    }

    function _setClearingConfig(
        address lendingPool,
        uint256 epoch,
        ClearingConfiguration memory clearingConfig,
        bool isOverridden
    ) private {
        ILendingPool(lendingPool).verifyClearingConfig(clearingConfig);

        AppliedClearingConfiguration storage appliedConfing = clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch];

        appliedConfing.config = clearingConfig;
        appliedConfing.isOverridden = isOverridden;
        appliedConfing.isSet = true;

        emit ClearingConfigSet(lendingPool, epoch, clearingConfig);
    }

    function _getLendingPoolClearingConfig(address lendingPool) private view returns (ClearingConfiguration memory) {
        return ILendingPool(lendingPool).getClearingConfig();
    }

    function _getLendingPoolBalance(address lendingPool) private view returns (LendingPoolBalance memory) {
        uint256 lendingPoolAvailableFunds = ILendingPool(lendingPool).getAvailableFunds();
        uint256 lendingPooluserOwedAmount = ILendingPool(lendingPool).getUserOwedAmount();

        return LendingPoolBalance(lendingPoolAvailableFunds, lendingPooluserOwedAmount);
    }
}
