// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./utils/LendingPoolTestUtils.sol";

contract LendingPoolTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_requestDeposit() public {
        // ARRANGE
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();

        // ACT
        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(
            alice, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount_alice
        );

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(
            bob, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[1], requestDepositAmount_bob
        );

        // ASSERT
        assertApproxEqAbs(mockUsdc.balanceOf(address(lendingPoolDeployment.pendingPool)), 350 * 10 ** 6, 0);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId_alice), alice);
        assertEq(pendingPool.ownerOf(dNftId_bob), bob);

        DepositNftDetails memory depositNftDetails_alice = pendingPool.trancheDepositNftDetails(dNftId_alice);
        assertEq(depositNftDetails_alice.assetAmount, requestDepositAmount_alice);

        DepositNftDetails memory depositNftDetails_bob = pendingPool.trancheDepositNftDetails(dNftId_bob);
        assertEq(depositNftDetails_bob.assetAmount, requestDepositAmount_bob);
    }

    function test_acceptDeposit() public {
        // ARRANGE
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        address lendingPoolAddress = lendingPoolDeployment.lendingPool;
        address juniorTrancheAddress = lendingPoolDeployment.tranches[0];
        address mezzoTrancheAddress = lendingPoolDeployment.tranches[1];

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice =
            _requestDeposit(alice, lendingPoolAddress, juniorTrancheAddress, requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, requestDepositAmount_bob);

        // ACT
        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        console2.log(juniorTrancheAddress);
        _acceptDeposit(alice, lendingPoolAddress, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDeposit(bob, lendingPoolAddress, dNftId_bob, acceptedDepositAmount_bob);

        // ASSERT
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        assertEq(lendingPool.totalSupply(), acceptDepositAmount_alice + acceptedDepositAmount_bob);
        assertEq(ILendingPoolTranche(juniorTrancheAddress).totalSupply(), acceptDepositAmount_alice * 10 ** 12);
        assertEq(ILendingPoolTranche(mezzoTrancheAddress).totalSupply(), acceptedDepositAmount_bob * 10 ** 12);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId_alice), alice);
        DepositNftDetails memory depositNftDetails_alice = pendingPool.trancheDepositNftDetails(dNftId_alice);
        assertEq(depositNftDetails_alice.assetAmount, requestDepositAmount_alice - acceptDepositAmount_alice);

        assertEq(pendingPool.ownerOf(dNftId_bob), address(0));
    }

    function test_requestWithdrawal() public {
        //        // arrange
        //        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        //
        //        uint256 requestDepositAmount_alice = 100 * 1e6;
        //        uint256 dNftId = _requestDeposit(
        //            alice, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount_alice
        //        );
        //
        //        uint256 requestDepositAmount_bob = 250 * 1e6;
        //        uint256 dNftId_bob = _requestDeposit(
        //            bob, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[1], requestDepositAmount_bob
        //        );
        //
        //        _acceptDeposit(
        //            lendingPoolDeployment.pendingPool,
        //            lendingPoolDeployment.lendingPool,
        //            lendingPoolDeployment.tranches[0],
        //            requestDepositAmount_alice
        //        );
        //
        //        // act
        //        uint256 requestWithdrawalAmount_alice = 50 * 1e6;
        //        uint256 wNftId_alice = _requestWithdrawal(
        //            alice, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestWithdrawalAmount_alice
        //        );
        //
        //        uint256 requestWithdrawalAmount_bob = 250 * 1e6;
        //        uint256 wNftId_bob = _requestWithdrawal(
        //            bob, lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestWithdrawalAmount_bob
        //        );
        //
        //        // assert
        //        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        //        assertEq(pendingPool.ownerOf(wNftId_alice), alice);
        //        assertEq(pendingPool.ownerOf(wNftId_bob), alice);
        //        assertEq(depositNftDetails_alice.assetAmount, requestDepositAmount_alice);
        //
        //        //        DepositNftDetails memory depositNftDetails_bob = pendingPool.trancheDepositNftDetails(dNftId_bob);
        //        //        assertEq(depositNftDetails_bob.assetAmount, requestDepositAmount_bob);
    }

    function test_acceptWithdrawal() public {}

    function test_cancelDeposit() public {}

    function test_cancelWithdrawalRequest() public {}
}
