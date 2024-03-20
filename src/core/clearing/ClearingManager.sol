// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearingManager.sol";
import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "./PendingRequestsPriorityCalculation.sol";
import "./AcceptedRequestsCalculation.sol";

abstract contract ClearingManager is
    IClearingManager,
    PendingRequestsPriorityCalculation,
    AcceptedRequestsCalculation
{
    // epochId => ClearingConfiguration
    mapping(uint256 => ClearingConfiguration) public clearingConfigPerEpoch;

    function registerClearingConfig(uint256 epoch, ClearingConfiguration calldata clearingConfig) external {
        // TODO: check values before setting
        _setClearingConfig(epoch, clearingConfig, true);
    }

    function doClearing(
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external {
        // step 1
        if (pendingRequestsPerEpoch[targetEpoch].status != PendingRequestsTaskStatus.ENDED) {
            calculatePendingRequestsPriority(pendingRequestsPriorityCalculationBatchSize, targetEpoch);
        }
        // step 2
        if (
            pendingRequestsPerEpoch[targetEpoch].status == PendingRequestsTaskStatus.ENDED
                && !acceptedRequestsCalculationPerEpochStatus[targetEpoch]
        ) {
            ClearingInput memory clearingInput = ClearingInput(
                _createClearingConfig(targetEpoch),
                _getLendingPoolBalance(),
                pendingRequestsPerEpoch[targetEpoch].pendingDeposits,
                pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals,
                targetEpoch
            );
            calculateAcceptedRequests(clearingInput);
        }
    }

    function getClearingConfig(uint256 epoch) external view returns (ClearingConfiguration memory) {
        return clearingConfigPerEpoch[epoch];
    }

    //*** Helper Methods ***/

    function _createClearingConfig(uint256 targetEpoch) private returns (ClearingConfiguration memory) {
        if (clearingConfigPerEpoch[targetEpoch].isOverridden) {
            return clearingConfigPerEpoch[targetEpoch];
        }
        ClearingConfiguration memory clearingConfiguration = _createClearingConfigFromPoolConfig();
        _setClearingConfig(targetEpoch, clearingConfiguration, false);
        return clearingConfiguration;
    }

    function _setClearingConfig(uint256 epoch, ClearingConfiguration memory clearingConfig, bool isOverridden)
        private
    {
        clearingConfigPerEpoch[epoch].borrowAmount = clearingConfig.borrowAmount;
        clearingConfigPerEpoch[epoch].maxExcessPercentage = clearingConfig.maxExcessPercentage;
        clearingConfigPerEpoch[epoch].minExcessPercentage = clearingConfig.minExcessPercentage;
        clearingConfigPerEpoch[epoch].trancheDesiredRatios = new uint256[](clearingConfig.trancheDesiredRatios.length);
        for (uint256 i; i < clearingConfig.trancheDesiredRatios.length; ++i) {
            clearingConfigPerEpoch[epoch].trancheDesiredRatios[i] = clearingConfig.trancheDesiredRatios[i];
        }
        clearingConfigPerEpoch[epoch].isOverridden = isOverridden;
    }

    //*** Virtual Methods ***/

    function _createClearingConfigFromPoolConfig() internal virtual returns (ClearingConfiguration memory);

    function _getLendingPoolBalance() internal virtual returns (LendingPoolBalance memory);
}
