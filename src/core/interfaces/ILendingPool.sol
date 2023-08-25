// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface ILendingPool {
    function deposit(address tranche, uint256 amount) external returns (uint256);

    function withdraw(address tranche, uint256 amount) external returns (uint256);

    function applyYield(uint128 yield) external returns (uint256);
}
