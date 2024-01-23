// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {LendingPoolTestUtils} from "./LendingPoolTestUtils.sol";
import "../../../src/core/lendingPool/PendingPool.sol";

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
}
