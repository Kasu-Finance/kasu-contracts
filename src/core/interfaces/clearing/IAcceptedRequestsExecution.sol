// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IAcceptedRequestsExecution {
    function executeAcceptedRequests(
        uint256[][][] memory tranchePriorityDepositsAccepted,
        uint256[] memory acceptedPriorityWithdrawalAmounts
    ) external;
}
