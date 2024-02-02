// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ILendingPoolManager.sol";

struct TrancheDetail {
    bool isEnabled;
    uint256 ratio;
    uint256 interestRate;
}

struct PoolConfiguration {
    string name;
    string symbol;
    address usdcAddress;
    uint256 minDepositAmount;
    uint256 targetExcessLiquidity;
    Tranches tranches;
    address poolAdmin;
    address borrowRecipient;
}

struct Tranches {
    TrancheDetail junior;
    TrancheDetail mezzo;
    TrancheDetail senior;
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
