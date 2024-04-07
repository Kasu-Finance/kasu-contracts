// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IClearingStepsData.sol";

/**
 * @notice Clearing calculation input.
 * @custom:member config Clearing configuration.
 * @custom:member balance Lending pool balances.
 * @custom:member pendingDeposits Pending deposits.
 * @custom:member pendingWithdrawals Pending withdrawals.
 */
struct ClearingInput {
    ClearingConfiguration config;
    LendingPoolBalance balance;
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
}

/**
 * @notice Lending pool balances.
 * @custom:member excess Lending pool excess balance. Lending pool available assets.
 * @custom:member owed Owed balance.
 */
struct LendingPoolBalance {
    uint256 excess;
    uint256 owed;
}

interface IAcceptedRequestsCalculation {
    function calculateAcceptedRequests(ClearingInput calldata input)
        external
        view
        returns (
            uint256[][][] memory tranchePriorityDepositsAccepted,
            uint256[] memory acceptedPriorityWithdrawalAmounts
        );

    error DrawAmountExceedsAvailable(uint256 desiredDrawAmount, uint256 maximumAvailableToDraw);
    error InvalidDepositResult();
    error InvalidWithdrawalResult();
    error InvalidResult();
}
