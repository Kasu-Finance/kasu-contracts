// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct PendingDeposits {
    uint256 totalDepositAmount;
    uint256[] trancheDepositsAmounts;
    // array by tranche and priority
    uint256[][] tranchePriorityDepositsAmounts;
}

struct PendingWithdrawals {
    uint256 totalWithdrawalsAmount;
    // array by priority
    uint256[] priorityWithdrawalAmounts;
}

error PendingRequestsPriorityCalculationIsPending();

interface IClearingCalculations {
    function calculatePendingRequestsPriority() external;

    function isPendingRequestsPriorityCalculationPending() external returns (bool);
}
