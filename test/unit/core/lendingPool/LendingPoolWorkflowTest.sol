// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./utils/LendingPoolTestUtils.sol";
import {
    Tranches,
    TrancheDetail
} from "../../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";

contract LendingPoolTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_complete_user_workflow_using_multiple_users_and_lending_pools() public {
        // ### ARRANGE ###
        // Lending Pool 1
        Tranches memory tranches1;
        tranches1.junior = TrancheDetail(true, 10_00, 20_00);
        tranches1.mezzo = TrancheDetail(true, 20_00, 10_00);
        tranches1.senior = TrancheDetail(true, 70_00, 5_00);
        PoolConfiguration memory poolConfiguration1 =
            PoolConfiguration("Test Lending Pool1", "TLP1", address(mockUsdc), 1 ether, 50_000 * 1e6, tranches1);
        LendingPoolDeployment memory lendingPoolDeployment1 = createLendingPool(poolConfiguration1);
        // Lending Pool 2
        Tranches memory tranches2;
        tranches2.junior = TrancheDetail(true, 15_00, 20_00);
        tranches2.mezzo = TrancheDetail(false, 0, 0);
        tranches2.senior = TrancheDetail(true, 85_00, 5_00);
        PoolConfiguration memory poolConfiguration2 =
            PoolConfiguration("Test Lending Pool2", "TLP2", address(mockUsdc), 1 ether, 20_000 * 1e6, tranches2);
        LendingPoolDeployment memory lendingPoolDeployment2 = createLendingPool(poolConfiguration2);
        // ### ACT ###
    }
}
