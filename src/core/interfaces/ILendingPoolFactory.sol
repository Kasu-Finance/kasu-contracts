// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct PoolConfiguration {
    uint256 maxDepositAmount;
    uint256 poolCap;
    uint256[] trancheRatio;
}

interface ILendingPoolFactory {
    function createPool(PoolConfiguration calldata poolConfiguration) external returns (address);
}
