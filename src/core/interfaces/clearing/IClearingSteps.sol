// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IAcceptedRequestsExecution.sol";
import "./IAcceptedRequestsCalculation.sol";
import "./IPendingRequestsPriorityCalculation.sol";
import "./IClearingStepsData.sol";

interface IClearingSteps is
    IPendingRequestsPriorityCalculation,
    IAcceptedRequestsExecution,
    IAcceptedRequestsCalculation
{
    // Getters

    function getPendingDeposits(uint256 epoch) external view returns (PendingDeposits memory);

    function getPendingWithdrawals(uint256 epoch) external view returns (PendingWithdrawals memory);

    function getTranchePriorityDepositsAccepted(uint256 epoch) external view returns (uint256[][][] memory);

    function getAcceptedPriorityWithdrawalAmounts(uint256 epoch) external view returns (uint256[] memory);
}
