// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsExecution.sol";
import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";
import "./IClearingStepsData.sol";

interface IClearingSteps is IPendingRequestsPriorityCalculation, IAcceptedRequestsExecution {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function clearingData(uint256 epoch) external view returns (ClearingData memory);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function calculateAndSaveAcceptedRequests(
        ClearingConfiguration memory config,
        LendingPoolBalance memory balance,
        uint256 targetEpoch
    ) external;

    /* ========== ERRORS ========== */

    error CannotFindTranche(address tranche);
}
