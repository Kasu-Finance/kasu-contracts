// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IPendingRequestsPriorityCalculation.sol";

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
 * @notice Clearing configuration.
 * @custom:member borrowAmount Desired borrow amount for current clearing.
 * @custom:member trancheDesiredRatios Lending pool ranche desired ratios in percentages.
 * @custom:member maxExcessPercentage Maximum excess balance percentage.
 * @custom:member minExcessPercentage Minimum excess balance percentage.
 */
struct ClearingConfiguration {
    uint256 borrowAmount;
    uint256[] trancheDesiredRatios;
    uint256 maxExcessPercentage;
    uint256 minExcessPercentage;
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

    error BorrowAmountExceedsAvailable(uint256 desiredBorrowAmount, uint256 maximumAvailableToBorrow);
    error InvalidDepositResult();
    error InvalidWithdrawalResult();
    error InvalidResult();
}
