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

/**
 * @title ClearingCoordinator contract
 * @notice Contract responsible for coordinating clearing process for all lending pools.
 * @dev Clearing process is divided into 5 steps:
 * 1. Apply lending pool interests  for the target epoch.
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

    /// @notice lendingPoolAddress => nextClearingEpoch
    mapping(address lendingPool => uint256 nextClearingEpoch) public nextLendingPoolClearingEpoch;
    /// @notice lendingPoolAddress => epochId => ClearingStatus
    mapping(address lendingPool => mapping(uint256 epoch => ClearingStatus)) public lendingPoolClearingStatus;
    /// @notice lendingPoolAddress => epochId => ClearingConfiguration
    mapping(address lendingPool => mapping(uint256 epoch => AppliedClearingConfiguration)) public
        clearingConfigPerLendingPoolAndEpoch;

    constructor(ISystemVariables systemVariables_, IUserManager userManager_, ILendingPoolManager lendingPoolManager_)
        LendingPoolHelpers(lendingPoolManager_)
    {
        systemVariables = systemVariables_;
        userManager = userManager_;
    }

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

    function initializeLendingPool(address lendingPool) external onlyLendingPoolManager {
        nextLendingPoolClearingEpoch[lendingPool] = systemVariables.getCurrentRequestEpoch();
    }

    function overwriteClearingConfig(
        address lendingPool,
        uint256 targetEpoch,
        ClearingConfiguration calldata clearingConfig
    ) external onlyLendingPoolManager {
        if (nextLendingPoolClearingEpoch[lendingPool] != targetEpoch) {
            revert InvalidClearingTargetEpochForLendingPool(
                lendingPool, targetEpoch, nextLendingPoolClearingEpoch[lendingPool]
            );
        }

        if (lendingPoolClearingStatus[lendingPool][targetEpoch] > ClearingStatus.STEP3_PENDING) {
            revert CannotOverrideClearingConfig(lendingPool, targetEpoch);
        }

        // TODO: check values before setting
        _setClearingConfig(lendingPool, targetEpoch, clearingConfig, true);
    }

    function setDefaultClearingConfig(address lendingPool, uint256 epoch) public onlyLendingPoolManager {
        if (lendingPoolClearingStatus[lendingPool][epoch] >= ClearingStatus.STEP3_PENDING) {
            revert CannotOverrideClearingConfig(lendingPool, epoch);
        }
        ClearingConfiguration memory clearingConfiguration = _getLendingPoolClearingConfig(lendingPool);
        _setClearingConfig(lendingPool, epoch, clearingConfiguration, false);
    }

    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external onlyLendingPoolManager {
        ClearingStatus clearingStatus = lendingPoolClearingStatus[lendingPoolAddress][targetEpoch];

        if (clearingStatus == ClearingStatus.ENDED) {
            revert ClearingAlreadyExecuted(targetEpoch);
        }

        // check if clearing for target epoch is valid
        if (clearingStatus == ClearingStatus.UNINITIALISED) {
            if (nextLendingPoolClearingEpoch[lendingPoolAddress] != targetEpoch) {
                revert InvalidClearingTargetEpochForLendingPool(
                    lendingPoolAddress, targetEpoch, nextLendingPoolClearingEpoch[lendingPoolAddress]
                );
            }
        }

        bool isPastClearingTime;
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();
        if (targetEpoch == currentEpoch) {
            if (!systemVariables.isClearingTime()) {
                revert TargetEpochClearingNotStarted(targetEpoch);
            }
        } else {
            isPastClearingTime = true;
        }

        if (clearingStatus == ClearingStatus.UNINITIALISED) {
            clearingStatus = ClearingStatus.STEP1_PENDING;
        }

        // Step 1 - Apply interests to the lending pool tranches for the target epoch
        if (clearingStatus == ClearingStatus.STEP1_PENDING) {
            ILendingPool(lendingPoolAddress).applyInterests(targetEpoch);

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

        IClearingSteps _clearingSteps = IClearingSteps(ILendingPool(lendingPoolAddress).getPendingPool());

        // Step 2 - Calculate pending deposit and withdrawal request priorities
        if (clearingStatus == ClearingStatus.STEP2_PENDING) {
            // if clearing step 1 is run after epoch end, end clearing for target epoch
            if (isPastClearingTime) {
                clearingStatus = ClearingStatus.ENDED;
            } else {
                _clearingSteps.calculatePendingRequestsPriorityBatch(
                    pendingRequestsPriorityCalculationBatchSize, targetEpoch
                );

                if (_clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED) {
                    clearingStatus = ClearingStatus.STEP3_PENDING;
                }
            }
        }

        // Step 3 - Calculate accepted deposit and withdrawal amount for each tranche and priority
        if (clearingStatus == ClearingStatus.STEP3_PENDING) {
            _clearingSteps.calculateAndSaveAcceptedRequests(
                getClearingConfig(lendingPoolAddress, targetEpoch),
                _getLendingPoolBalance(lendingPoolAddress),
                targetEpoch
            );

            clearingStatus = ClearingStatus.STEP4_PENDING;
        }

        // Step 4 - Process accepted deposit and accepted withdrawal requests
        if (clearingStatus == ClearingStatus.STEP4_PENDING) {
            _clearingSteps.executeAcceptedRequestsBatch(targetEpoch, acceptedRequestsExecutionBatchSize);

            if (_clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.ENDED) {
                clearingStatus = ClearingStatus.STEP5_PENDING;
            }
        }

        // Step 5 - Draw funds
        if (clearingStatus == ClearingStatus.STEP5_PENDING) {
            if (clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch].config.drawAmount > 0) {
                ILendingPool(lendingPoolAddress).drawFunds(
                    clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch].config.drawAmount
                );
            }

            clearingStatus = ClearingStatus.ENDED;
        }

        lendingPoolClearingStatus[lendingPoolAddress][targetEpoch] = clearingStatus;

        if (clearingStatus == ClearingStatus.ENDED) {
            nextLendingPoolClearingEpoch[lendingPoolAddress] = targetEpoch + 1;
        }

        // emit clearing was executed and at which step it ended
        emit ClearingExecuted(lendingPoolAddress, targetEpoch, clearingStatus);
    }

    function getClearingConfig(address lendingPool, uint256 targetEpoch)
        public
        returns (ClearingConfiguration memory)
    {
        if (
            !clearingConfigPerLendingPoolAndEpoch[lendingPool][targetEpoch].isSet
                && !clearingConfigPerLendingPoolAndEpoch[lendingPool][targetEpoch].isOverwritten
        ) {
            ClearingConfiguration memory clearingConfiguration = _getLendingPoolClearingConfig(lendingPool);
            setDefaultClearingConfig(lendingPool, targetEpoch);
        }
        return clearingConfigPerLendingPoolAndEpoch[lendingPool][targetEpoch].config;
    }

    //*** Helper Methods ***/

    function _setClearingConfig(
        address lendingPool,
        uint256 epoch,
        ClearingConfiguration memory clearingConfig,
        bool isOverridden
    ) private {
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config.drawAmount = clearingConfig.drawAmount;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config.maxExcessPercentage =
            clearingConfig.maxExcessPercentage;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config.minExcessPercentage =
            clearingConfig.minExcessPercentage;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config.trancheDesiredRatios =
            new uint256[](clearingConfig.trancheDesiredRatios.length);
        for (uint256 i; i < clearingConfig.trancheDesiredRatios.length; ++i) {
            clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].config.trancheDesiredRatios[i] =
                clearingConfig.trancheDesiredRatios[i];
        }
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].isOverwritten = isOverridden;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].isSet = true;
    }

    function _getLendingPoolClearingConfig(address lendingPoolAddress) private returns (ClearingConfiguration memory) {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);

        // TODO: ideally update to only fetch necessary data
        PoolConfiguration memory poolConfig = lendingPool.poolConfiguration();
        uint256[] memory trancheRatios = new uint256[](poolConfig.tranches.length);
        for (uint256 i; i < poolConfig.tranches.length; ++i) {
            trancheRatios[i] = poolConfig.tranches[i].ratio;
        }

        ClearingConfiguration memory clearingConfiguration = ClearingConfiguration(
            poolConfig.desiredDrawAmount,
            trancheRatios,
            poolConfig.targetExcessLiquidityPercentage,
            poolConfig.minimumExcessLiquidityPercentage
        );
        return clearingConfiguration;
    }

    function _getLendingPoolBalance(address lendingPoolAddress) private view returns (LendingPoolBalance memory) {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        uint256 lendingPooluserOwedAmount = lendingPool.getUserOwedAmount();
        LendingPoolBalance memory lendingPoolBalance =
            LendingPoolBalance(lendingPool.totalSupply() - lendingPooluserOwedAmount, lendingPooluserOwedAmount);
        return lendingPoolBalance;
    }
}
