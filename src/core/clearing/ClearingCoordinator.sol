// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearingCoordinator.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "../lendingPool/LendingPoolHelpers.sol";
import "../interfaces/clearing/IClearingSteps.sol";

enum ClearingStatus {
    UNINITIALISED,
    STEP1_PENDING,
    STEP2_PENDING,
    STEP3_PENDING,
    STEP4_PENDING,
    ENDED
}

contract ClearingCoordinator is IClearingCoordinator, LendingPoolHelpers {
    /// @notice lendingPoolAddress => epochId => ClearingStatus
    mapping(address => mapping(uint256 => ClearingStatus)) public lendingPoolClearingStatus;
    /// @notice lendingPoolAddress => epochId => ClearingConfiguration
    mapping(address => mapping(uint256 => ClearingConfiguration)) public clearingConfigPerLendingPoolAndEpoch;
    /// @notice lendingPoolAddress => epochId => isCalculated
    mapping(address => mapping(uint256 => bool)) public acceptedRequestsCalculationPerEpochStatus;

    constructor(ILendingPoolManager lendingPoolManager_) LendingPoolHelpers(lendingPoolManager_) {}

    function registerClearingConfig(address lendingPool, uint256 epoch, ClearingConfiguration calldata clearingConfig)
        external
        onlyLendingPoolManager
    {
        // TODO: check values before setting
        _setClearingConfig(lendingPool, epoch, clearingConfig, true);
    }

    function doClearing(
        address lendingPoolAddress,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external onlyLendingPoolManager {
        // TODO: verify previous clearing has ended
        // TODO: check if clearing time

        ClearingStatus clearingStatus = lendingPoolClearingStatus[lendingPoolAddress][targetEpoch];

        if (clearingStatus == ClearingStatus.ENDED) {
            revert ClearingAlreadyExecuted(targetEpoch);
        }

        // apply interests before clearing
        if (clearingStatus == ClearingStatus.UNINITIALISED) {
            ILendingPool(lendingPoolAddress).applyInterests(targetEpoch);

            clearingStatus = ClearingStatus.STEP1_PENDING;

            // TODO: if no pending requests, skip to step 4
            // TODO: if clearing is run after epoch end, end clearing
        }

        IClearingSteps _clearingSteps =
            IClearingSteps(ILendingPool(lendingPoolAddress).lendingPoolInfo().pendingPoolAddress);

        // step 1
        if (clearingStatus == ClearingStatus.STEP1_PENDING) {
            _clearingSteps.calculatePendingRequestsPriorityBatch(
                pendingRequestsPriorityCalculationBatchSize, targetEpoch
            );

            if (_clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED) {
                clearingStatus = ClearingStatus.STEP2_PENDING;
            }
        }

        // step 2
        if (clearingStatus == ClearingStatus.STEP2_PENDING) {
            _clearingSteps.calculateAndSaveAcceptedRequests(
                _createClearingConfig(lendingPoolAddress, targetEpoch),
                _getLendingPoolBalance(lendingPoolAddress),
                targetEpoch
            );

            if (_clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.UNINITIALISED) {
                _clearingSteps.init(targetEpoch);
            }

            acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch] = true;
            clearingStatus = ClearingStatus.STEP3_PENDING;
        }

        // step 3
        if (clearingStatus == ClearingStatus.STEP3_PENDING) {
            _clearingSteps.executeAcceptedRequestsBatch(targetEpoch, acceptedRequestsExecutionBatchSize);

            if (_clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.ENDED) {
                clearingStatus = ClearingStatus.STEP4_PENDING;
            }
        }

        // step 4
        if (clearingStatus == ClearingStatus.STEP4_PENDING) {
            ILendingPool(lendingPoolAddress).borrowLoan(
                clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch].borrowAmount
            );

            clearingStatus = ClearingStatus.ENDED;
        }

        lendingPoolClearingStatus[lendingPoolAddress][targetEpoch] = clearingStatus;
    }

    function getClearingConfig(address lendingPool, uint256 epoch)
        external
        view
        returns (ClearingConfiguration memory)
    {
        return clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch];
    }

    //*** Helper Methods ***/

    function _createClearingConfig(address lendingPoolAddress, uint256 targetEpoch)
        private
        returns (ClearingConfiguration memory)
    {
        if (clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch].isOverridden) {
            return clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch];
        }
        ClearingConfiguration memory clearingConfiguration = _getLendingPoolClearingConfig(lendingPoolAddress);
        _setClearingConfig(lendingPoolAddress, targetEpoch, clearingConfiguration, false);
        return clearingConfiguration;
    }

    function _setClearingConfig(
        address lendingPool,
        uint256 epoch,
        ClearingConfiguration memory clearingConfig,
        bool isOverridden
    ) private {
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].borrowAmount = clearingConfig.borrowAmount;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].maxExcessPercentage =
            clearingConfig.maxExcessPercentage;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].minExcessPercentage =
            clearingConfig.minExcessPercentage;
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].trancheDesiredRatios =
            new uint256[](clearingConfig.trancheDesiredRatios.length);
        for (uint256 i; i < clearingConfig.trancheDesiredRatios.length; ++i) {
            clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].trancheDesiredRatios[i] =
                clearingConfig.trancheDesiredRatios[i];
        }
        clearingConfigPerLendingPoolAndEpoch[lendingPool][epoch].isOverridden = isOverridden;
    }

    function _getLendingPoolClearingConfig(address lendingPoolAddress) private returns (ClearingConfiguration memory) {
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        PoolConfiguration memory poolConfig = lendingPool.poolConfiguration();
        uint256[] memory trancheRatios = new uint256[](poolConfig.tranches.length);
        for (uint256 i; i < poolConfig.tranches.length; ++i) {
            trancheRatios[i] = poolConfig.tranches[i].ratio;
        }
        uint256 lendingPoolBalance = lendingPool.totalSupply();
        uint256 borrowAmount = lendingPoolBalance < poolConfig.totalDesiredLoanAmount
            ? 0
            : lendingPoolBalance - poolConfig.totalDesiredLoanAmount;
        ClearingConfiguration memory clearingConfiguration = ClearingConfiguration(
            borrowAmount,
            trancheRatios,
            poolConfig.targetExcessLiquidityPercentage,
            poolConfig.minimumExcessLiquidityPercentage,
            false
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
