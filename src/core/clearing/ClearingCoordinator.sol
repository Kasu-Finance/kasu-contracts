// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearingManager.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "../lendingPool/LendingPoolHelpers.sol";
import "../interfaces/clearing/IClearingSteps.sol";

contract ClearingCoordinator is IClearingCoordinator, LendingPoolHelpers {
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
        IClearingSteps _clearingSteps =
            IClearingSteps(ILendingPool(lendingPoolAddress).lendingPoolInfo().pendingPoolAddress);
        if (
            _clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED
                && acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch]
                && _clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.ENDED
        ) {
            revert ClearingAlreadyExecuted(targetEpoch);
        }

        // step 1
        if (_clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) != TaskStatus.ENDED) {
            _clearingSteps.calculatePendingRequestsPriorityBatch(
                pendingRequestsPriorityCalculationBatchSize, targetEpoch
            );
        }

        // step 2
        if (
            _clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED
                && !acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch]
        ) {
            ClearingInput memory clearingInput = ClearingInput(
                _createClearingConfig(lendingPoolAddress, targetEpoch),
                _getLendingPoolBalance(lendingPoolAddress),
                _clearingSteps.getPendingDeposits(targetEpoch),
                _clearingSteps.getPendingWithdrawals(targetEpoch),
                targetEpoch
            );

            _clearingSteps.calculateAndSaveAcceptedRequests(clearingInput);

            if (_clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.UNINITIALISED) {
                _clearingSteps.init(targetEpoch);
            }

            acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch] = true;
        }

        // step 3
        if (
            _clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED
                && acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch]
                && _clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) != TaskStatus.ENDED
        ) {
            _clearingSteps.executeAcceptedRequestsBatch(targetEpoch, acceptedRequestsExecutionBatchSize);
        }

        // step 4
        if (
            _clearingSteps.pendingRequestsPriorityCalculationStatus(targetEpoch) == TaskStatus.ENDED
                && acceptedRequestsCalculationPerEpochStatus[lendingPoolAddress][targetEpoch]
                && _clearingSteps.acceptedRequestsExecutionPerEpochStatus(targetEpoch) == TaskStatus.ENDED
        ) {
            ILendingPool(lendingPoolAddress).borrowLoan(
                clearingConfigPerLendingPoolAndEpoch[lendingPoolAddress][targetEpoch].borrowAmount
            );
        }
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
        uint256 lendingPoolBorrowedAmount = lendingPool.getBorrowedAmount();
        LendingPoolBalance memory lendingPoolBalance =
            LendingPoolBalance(lendingPool.totalSupply() - lendingPoolBorrowedAmount, lendingPoolBorrowedAmount);
        return lendingPoolBalance;
    }
}
