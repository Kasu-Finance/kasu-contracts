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
        uint256 dNftId = _requestDeposit(
            alice, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );

        // assert
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 0, 0);
        assertApproxEqAbs(mockUsdc.balanceOf(address(lendingPoolDeployment.pendingPool)), requestDepositAmount, 0);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId), alice);

        DepositNftDetails memory depositNftDetails = pendingPool.trancheDepositNftDetails(dNftId);
        assertEq(depositNftDetails.assetAmount, requestDepositAmount);
        // TODO: assert epochId, priorityLevel
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
        uint256 dNftId = _requestDeposit(
            alice, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );

        // act
        uint256 acceptDepositAmount = 100 * 1e6;
        _acceptDeposit(
            lendingPoolDeployment.pendingPool,
            lendingPoolDeployment.lendingPool,
            lendingPoolDeployment.tranches[0],
            acceptDepositAmount
        );

        // assert
        ILendingPool lendingPool = ILendingPool(lendingPoolDeployment.lendingPool);
        assertEq(lendingPool.balanceOf(lendingPoolDeployment.tranches[0]), acceptDepositAmount);
        assertEq(lendingPool.totalSupply(), acceptDepositAmount);
        assertEq(
            ILendingPoolTranche(lendingPoolDeployment.tranches[0]).balanceOf(alice), acceptDepositAmount * 10 ** 12
        );
    }
}
