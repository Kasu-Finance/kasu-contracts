// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";

contract AcceptedRequestsExecution is IAcceptedRequestsExecution {
    function executeAcceptedRequests(
        uint256[][][] memory tranchePriorityDepositsAccepted,
        uint256[] memory acceptedPriorityWithdrawalAmounts
    ) external {}

    // function _getTrancheTotalDepositsAmount(address tranche) internal returns (uint256);
}
