// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ILendingPoolManager.sol";

struct TrancheConfig {
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

struct PoolConfiguration {
    string name;
    string symbol;
    address usdcAddress;
    uint256 targetExcessLiquidity;
    TrancheConfig[] tranches;
    address poolAdmin;
    address borrowRecipient;
    uint256 totalDesiredLoanAmount;
}

struct LendingPoolDeployment {
    address lendingPool;
    address pendingPool;
    address[] tranches;
}

event PoolCreated(address indexed lendingPool, LendingPoolDeployment lendingPoolDeployment);

interface ILendingPoolFactory {
    function createPool(PoolConfiguration calldata poolConfiguration)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment);
}
