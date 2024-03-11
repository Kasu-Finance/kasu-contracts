// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ILendingPoolManager.sol";
import "./ILendingPool.sol";

struct LendingPoolDeployment {
    address lendingPool;
    address pendingPool;
    address[] tranches;
}

event PoolCreated(
    address indexed lendingPool, LendingPoolDeployment lendingPoolDeployment, PoolConfiguration poolConfiguration
);

struct CreateTrancheConfig {
    string trancheName;
    string trancheSymbol;
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

struct CreatePoolConfig {
    string poolName;
    string poolSymbol;
    uint256 targetExcessLiquidityPercentage;
    CreateTrancheConfig[] tranches;
    address poolAdmin;
    address borrowRecipient;
    uint256 totalDesiredLoanAmount;
}

interface ILendingPoolFactory {
    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment);
}
