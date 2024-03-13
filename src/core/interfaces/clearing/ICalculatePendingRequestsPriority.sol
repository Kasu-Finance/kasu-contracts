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

interface ICalculatePendingRequestsPriority {
    function calculatePendingRequestsPriority(uint256 batchSize, uint256 targetEpoch) external;

    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) external view returns (uint256);

    function getPendingDeposits(uint256 targetEpoch) external returns (PendingDeposits memory);

    function getPendingWithdrawals(uint256 targetEpoch) external returns (PendingWithdrawals memory);
}
