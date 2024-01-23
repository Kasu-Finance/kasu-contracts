// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./utils/LendingPoolTestUtils.sol";
import "../../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";

contract LendingPoolTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_when_alice_requests_deposit_then_funds_move_to_pending_pool() public {
        // arrange
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration = PoolConfiguration(
            "Test Lending Pool", "TLP", address(mockUsdc), minDepositAmount, targetExcessLiquidity, tranches
        );
        LendingPoolDeployment memory lendingPoolDeployment = createLendingPool(poolConfiguration);

        // act
        uint256 requestDepositAmount = 100 * 1e6;
        deal(address(mockUsdc), alice, requestDepositAmount, true);
        vm.startPrank(alice);
        mockUsdc.approve(address(lendingPoolManager), requestDepositAmount);
        uint256 dNftId = lendingPoolManager.requestDeposit(
            lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );
        vm.stopPrank();

        // assert
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 0, 0);
        assertApproxEqAbs(mockUsdc.balanceOf(address(lendingPoolDeployment.pendingPool)), requestDepositAmount, 0);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId), alice);

        DepositNftDetails memory depositNftDetails = pendingPool.trancheDepositNftDetails(dNftId);
        assertEq(depositNftDetails.assetAmount, requestDepositAmount);
        // TODO: assert epochId, priorityLevel
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

    function test_acceptDeposit_acceptAliceDeposit() public {
        // arrange
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration = PoolConfiguration(
            "Test Lending Pool", "TLP", address(mockUsdc), minDepositAmount, targetExcessLiquidity, tranches
        );
        LendingPoolDeployment memory lendingPoolDeployment = createLendingPool(poolConfiguration);

        // request deposit
        uint256 requestDepositAmount = 100 * 1e6;
        deal(address(mockUsdc), alice, requestDepositAmount, true);
        vm.startPrank(alice);
        mockUsdc.approve(address(lendingPoolManager), requestDepositAmount);
        uint256 dNftId = lendingPoolManager.requestDeposit(
            lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );
        vm.stopPrank();

        // act
        ILendingPool lendingPool = ILendingPool(lendingPoolDeployment.lendingPool);

        startHoax(lendingPoolDeployment.pendingPool);
        mockUsdc.approve(address(lendingPool), requestDepositAmount);
        lendingPool.acceptDeposit(lendingPoolDeployment.tranches[0], alice, requestDepositAmount);
        vm.stopPrank();

        // assert
        assertEq(lendingPool.balanceOf(lendingPoolDeployment.tranches[0]), requestDepositAmount);
        assertEq(lendingPool.totalSupply(), requestDepositAmount);
        assertEq(
            ILendingPoolTranche(lendingPoolDeployment.tranches[0]).balanceOf(alice), requestDepositAmount * 10 ** 12
        );
    }
}
