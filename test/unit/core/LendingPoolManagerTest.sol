// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import {LendingPoolFactory} from "../../../src/core/lendingPool/LendingPoolFactory.sol";
import "../../../src/core/lendingPool/LendingPoolManager.sol";
import "forge-std/Test.sol";
import "../../shared/MockERC20Permit.sol";
import "forge-std/console2.sol";

contract LendingPoolManagerTest is Test {
    LendingPoolManager internal lendingPoolManager;
    LendingPoolDeployment internal lendingPoolDeployment;
    MockERC20Permit mockUsdc;

    address internal admin = address(0xad);
    address internal alice = address(0xaaa);

    function setUp() public {
        // usdc
        mockUsdc = new MockERC20Permit("USDC", "USDC", 6);

        // lending pool
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration =
            PoolConfiguration(address(mockUsdc), minDepositAmount, targetExcessLiquidity, tranches);
        LendingPoolFactory lendingPoolFactory = new LendingPoolFactory();
        startHoax(admin);
        lendingPoolDeployment = lendingPoolFactory.createPool(poolConfiguration);

        // lending pool manager
        lendingPoolManager = new LendingPoolManager(address(mockUsdc));
        lendingPoolManager.registerLendingPool(lendingPoolDeployment);
    }

    function test_when_alice_requests_deposit_then_funds_move_to_pending_pool() public {
        // act
        uint256 requestDepositAmount = 100 * 1e6;
        deal(address(mockUsdc), alice, requestDepositAmount, true);
        vm.startPrank(alice);
        mockUsdc.approve(address(lendingPoolManager), requestDepositAmount);
        lendingPoolManager.requestDeposit(
            lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );
        vm.stopPrank();

        // assert
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 0, 0);
        assertApproxEqAbs(mockUsdc.balanceOf(address(lendingPoolDeployment.pendingPool)), requestDepositAmount, 0);
    }
}
