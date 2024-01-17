// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct TrancheDetail {
    bool isEnabled;
    uint256 ratio;
    uint256 interestRate;
}

struct PoolConfiguration {
    uint256 minDepositAmount;
    uint256 targetExcessLiquidity;
    Tranches tranches;
}

struct Tranches {
    TrancheDetail junior;
    TrancheDetail mezzo;
    TrancheDetail senior;
}

interface ILendingPoolFactory {
    function createPool(PoolConfiguration calldata poolConfiguration) external returns (address);
}
