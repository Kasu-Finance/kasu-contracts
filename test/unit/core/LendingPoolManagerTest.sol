// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import {LendingPoolFactory} from "../../../src/core/lendingPool/LendingPoolFactory.sol";
import "../../../src/core/lendingPool/LendingPoolManager.sol";
import "forge-std/Test.sol";

contract LendingPoolManagerTest is Test {
    LendingPoolManager internal lendingPoolManager;
    LendingPoolDeployment internal lendingPoolDeployment;

    address admin = address(0xad);

    function setUp() public {
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration =
            PoolConfiguration(minDepositAmount, targetExcessLiquidity, tranches);
        LendingPoolFactory lendingPoolFactory = new LendingPoolFactory();
        startHoax(admin);
        lendingPoolDeployment = lendingPoolFactory.createPool(poolConfiguration);

        lendingPoolManager = new LendingPoolManager();
        lendingPoolManager.registerLendingPool(lendingPoolDeployment);
    }

    function testLendingPoolManagerTest1() public {
        lendingPoolManager.requestDeposit(lendingPoolDeployment.pendingPool, lendingPoolDeployment.tranches[0], 1 ether);
    }
}
