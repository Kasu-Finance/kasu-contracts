// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ILendingPoolManager.sol";
import "./ILendingPool.sol";

struct LendingPoolDeployment {
    address lendingPool;
    address pendingPool;
    address[] tranches;
}

event PoolCreated(address indexed lendingPool, LendingPoolDeployment lendingPoolDeployment);

interface ILendingPoolFactory {
    function createPool(
        string calldata poolName,
        string calldata poolSymbol,
        PoolConfiguration calldata poolConfiguration
    ) external returns (LendingPoolDeployment memory lendingPoolDeployment);
}
