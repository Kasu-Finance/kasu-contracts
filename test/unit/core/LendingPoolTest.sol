// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "../../../src/core/lendingPool/LendingPoolStoppable.sol";
import "../../../src/shared/CommonErrors.sol";
import "../../shared/MockExchange.sol";
import "../../../src/core/DepositSwap.sol";

contract LendingPoolTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_requestDeposit() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ACT
        uint256 dNftId1_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], 50 * 10 ** 6);

        vm.prank(admin);
        systemVariables.setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(true);

        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], 50 * 10 ** 6);

        // request deposit on junior tranche when no locking took place
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(
            abi.encodeWithSelector(IPendingPool.UserCanOnlyDepositInJuniorTrancheIfHeHasLockedRKsu.selector, bob)
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6, "");
        vm.stopPrank();

        vm.prank(admin);
        systemVariables.setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(false);

        // request deposit on user that is not allowed
        vm.startPrank(userNotAllowed);
        deal(address(mockUsdc), userNotAllowed, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(IKasuAllowList.UserNotInAllowList.selector, userNotAllowed));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6, "");
        vm.stopPrank();

        // request deposit on user that was allowed and now is disallowed
        vm.prank(admin);
        kasuAllowList.disallowUser(bob);
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(IKasuAllowList.UserNotInAllowList.selector, bob));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6, "");
        vm.stopPrank();
        vm.prank(admin);
        kasuAllowList.allowUser(bob);

        _lock(bob, 50 ether, lockPeriod30);
        uint256 dNftId1_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6);
        uint256 dNftId2_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6);

        // transfer dNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).transferFrom(bob, alice, dNftId1_bob);
        vm.stopPrank();

        // approve dNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).approve(alice, dNftId1_bob);
        vm.stopPrank();

        // set approval dNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).setApprovalForAll(alice, true);
        vm.stopPrank();

        // ASSERT
        assertEq(dNftId1_bob, dNftId2_bob);
        assertApproxEqAbs(mockUsdc.balanceOf(address(lpd.pendingPool)), 350 * 10 ** 6, 0);

        PendingPool pendingPool = PendingPool(lpd.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId1_alice), alice);
        assertEq(pendingPool.ownerOf(dNftId1_bob), bob);

        DepositNftDetails memory depositNftDetails_alice = pendingPool.trancheDepositNftDetails(dNftId1_alice);
        assertEq(depositNftDetails_alice.assetAmount, 100 * 10 ** 6);
        assertEq(depositNftDetails_alice.tranche, lpd.tranches[1]);

        DepositNftDetails memory depositNftDetails_bob = pendingPool.trancheDepositNftDetails(dNftId1_bob);
        assertEq(depositNftDetails_bob.assetAmount, 250 * 10 ** 6);
        assertEq(depositNftDetails_bob.tranche, lpd.tranches[0]);
    }

    function test_cancelDeposit() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        address lendingPoolAddress = lendingPoolDeployment.lendingPool;
        address juniorTrancheAddress = lendingPoolDeployment.tranches[0];
        address mezzoTrancheAddress = lendingPoolDeployment.tranches[1];

        uint256 dNftId_alice = _requestDeposit(alice, lendingPoolAddress, juniorTrancheAddress, 100 * 10 ** 6);

        uint256 dNftId1_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, 250 * 10 ** 6);
        // ### ACT ###
        // incorrect nft owner
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, dNftId_alice));
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId_alice);

        // non existing dNftId
        uint256 dNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_nonExistent));
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId_nonExistent);

        _cancelDepositRequest(alice, lendingPoolAddress, dNftId_alice);
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId1_bob);

        // user requests after cancellation
        uint256 dNftId2_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, 250 * 10 ** 6);
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId2_bob);
        assertFalse(dNftId1_bob == dNftId2_bob);

        // ### ASSERT ###
        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);

        // dNft burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_alice));
        assertEq(pendingPool.ownerOf(dNftId_alice), address(0));
        assertEq(mockUsdc.balanceOf(alice), 100 * 10 ** 6);

        // dNft burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId1_bob));
        assertEq(pendingPool.ownerOf(dNftId1_bob), address(0));
        assertEq(mockUsdc.balanceOf(bob), 250 * 10 ** 6);
    }

    function test_acceptDeposit() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        address lendingPoolAddress = lendingPoolDeployment.lendingPool;
        address juniorTrancheAddress = lendingPoolDeployment.tranches[0];
        address mezzoTrancheAddress = lendingPoolDeployment.tranches[1];

        uint256 dNftId1_alice = _requestDeposit(alice, lendingPoolAddress, juniorTrancheAddress, 100 * 10 ** 6);

        uint256 dNftId1_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, 250 * 10 ** 6);

        // ### ACT ###
        // accept more assets than requested in total
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.TooManyAssetsRequested.selector, dNftId1_alice, 100 * 10 ** 6, 101 * 10 ** 6
            )
        );
        _acceptDepositRequest(lendingPoolAddress, dNftId1_alice, 101 * 10 ** 6);

        _acceptDepositRequest(lendingPoolAddress, dNftId1_alice, 40 * 10 ** 6);

        // accept more assets than are available to be requested
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.TooManyAssetsRequested.selector, dNftId1_alice, 60 * 10 ** 6, 61 * 10 ** 6
            )
        );
        _acceptDepositRequest(lendingPoolAddress, dNftId1_alice, 61 * 10 ** 6);

        _acceptDepositRequest(lendingPoolAddress, dNftId1_bob, 250 * 10 ** 6);

        // transfer tranche shares
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        ILendingPoolTranche(juniorTrancheAddress).transfer(alice, 10 * 10 ** 6);
        vm.stopPrank();

        // approve tranche shares
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NotSupported.selector));
        ILendingPoolTranche(juniorTrancheAddress).approve(alice, 10 * 10 ** 6);
        vm.stopPrank();

        // non existing dNftId
        uint256 dNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_nonExistent));
        _acceptDepositRequest(lendingPoolAddress, dNftId_nonExistent, 50 * 10 ** 6);

        // ### ASSERT ###
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        assertEq(lendingPool.totalSupply(), 290 * 10 ** 6);
        assertEq(ILendingPoolTranche(juniorTrancheAddress).totalSupply(), 40 * 10 ** 18);
        assertEq(ILendingPoolTranche(mezzoTrancheAddress).totalSupply(), 250 * 10 ** 18);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(mockUsdc.balanceOf(address(pendingPool)), 60 * 10 ** 6);

        assertEq(pendingPool.ownerOf(dNftId1_alice), alice);
        DepositNftDetails memory depositNftDetails_alice = pendingPool.trancheDepositNftDetails(dNftId1_alice);
        assertEq(depositNftDetails_alice.assetAmount, 60 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId1_bob));
        assertEq(pendingPool.ownerOf(dNftId1_bob), address(0));

        uint256 dNftId2_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, 250 * 10 ** 6);
        assertFalse(dNftId1_bob == dNftId2_bob);
    }

    function test_getPendingDepositAmountForCurrentEpoch() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 aliceDeposit1 = 100 * 10 ** 6;
        uint256 dNftId1_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], aliceDeposit1);
        uint256 aliceDeposit2 = 50 * 10 ** 6;
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], aliceDeposit2);

        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);
        uint256 dNftId2_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 100 * 10 ** 6);

        _cancelDepositRequest(bob, lpd.lendingPool, dNftId2_bob);

        skip(6 days);

        uint256 aliceAccepted = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId1_alice, aliceAccepted);

        uint256 carolDeposit = 301 * 10 ** 6;
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[1], carolDeposit);

        // ### ACT ###
        uint256 pendingDepositAmountForCurrentEpoch =
            IPendingPool(lpd.pendingPool).getPendingDepositAmountForCurrentEpoch();
        uint256 totalPendingDepositAmount = IPendingPool(lpd.pendingPool).totalPendingDepositAmount();

        // ### ASSERT ###
        uint256 currentEpochPending = aliceDeposit1 + aliceDeposit2 - aliceAccepted;
        assertEq(pendingDepositAmountForCurrentEpoch, currentEpochPending);
        assertEq(totalPendingDepositAmount, currentEpochPending + carolDeposit);
    }

    function test_requestWithdrawal() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);

        // ### ACT ###
        uint256 wNftId_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        uint256 wNftId1_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 100 * 10 ** 18);
        uint256 wNftId2_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 100 * 10 ** 18);

        // request more assets to withdraw than user has in its balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.InsufficientSharesBalance.selector,
                bob,
                lpd.lendingPool,
                lpd.tranches[1],
                50 * 10 ** 18,
                51 * 10 ** 18
            )
        );
        _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 51 * 10 ** 18);

        // transfer wNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).transferFrom(bob, alice, wNftId1_bob);
        vm.stopPrank();

        // approve dNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).approve(alice, wNftId1_bob);
        vm.stopPrank();

        // set approval dNFT
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
        IPendingPool(lpd.pendingPool).setApprovalForAll(alice, true);
        vm.stopPrank();

        // ### ASSERT ###
        assertTrue(wNftId1_bob == wNftId2_bob);
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertEq(lendingPool.totalSupply(), 290 * 10 ** 6);
        assertEq(ILendingPoolTranche(lpd.tranches[0]).totalSupply(), 40 * 10 ** 18);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).totalSupply(), 250 * 10 ** 18);

        assertEq(ILendingPoolTranche(lpd.tranches[0]).balanceOf(lpd.pendingPool), 40 * 10 ** 18);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(lpd.pendingPool), 200 * 10 ** 18);

        assertEq(IPendingPool(lpd.pendingPool).ownerOf(wNftId_alice), alice);
        WithdrawalNftDetails memory withdrawalNftDetails_alice =
            IPendingPool(lpd.pendingPool).trancheWithdrawalNftDetails(wNftId_alice);
        assertEq(withdrawalNftDetails_alice.sharesAmount, 40 * 10 ** 18);

        assertEq(IPendingPool(lpd.pendingPool).ownerOf(wNftId1_bob), bob);
        WithdrawalNftDetails memory withdrawalNftDetails_bob =
            IPendingPool(lpd.pendingPool).trancheWithdrawalNftDetails(wNftId1_bob);
        assertEq(withdrawalNftDetails_bob.sharesAmount, 200 * 10 ** 18);
    }

    function test_cancelWithdrawalRequest() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);
        uint256 dNftId_carol = _requestDeposit(carol, lpd.lendingPool, lpd.tranches[2], 50 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_carol, 50 * 10 ** 6);

        uint256 wNftId_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        uint256 wNftId1_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 200 * 10 ** 18);

        ForceWithdrawalInput[] memory input1 = new ForceWithdrawalInput[](1);
        input1[0] = ForceWithdrawalInput(lpd.tranches[2], carol, 50 * 10 ** 18);
        uint256 wNftId_carol = _batchForceWithdrawals(poolManagerAccount, lpd.lendingPool, input1)[0];

        // ### ACT ###
        // incorrect owner
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, wNftId_alice));
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId_alice);

        _cancelWithdrawalRequest(alice, lpd.lendingPool, wNftId_alice);
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId1_bob);

        // try to cancel forced withdrawal request
        vm.expectRevert(
            abi.encodeWithSelector(IPendingPool.CannotCancelSystemWithdrawalRequest.selector, carol, wNftId_carol)
        );
        _cancelWithdrawalRequest(carol, lpd.lendingPool, wNftId_carol);

        // non existing dNftId
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        _cancelWithdrawalRequest(carol, lpd.lendingPool, 1);

        uint256 wNftId2_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 10 * 10 ** 18);

        // ### ASSERT ###
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_alice));
        assertEq(pendingPool.ownerOf(wNftId_alice), address(0)); // wNft burned
        assertEq(mockUsdc.balanceOf(alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId1_bob));
        assertEq(pendingPool.ownerOf(wNftId1_bob), address(0)); // wNft burned
        assertEq(mockUsdc.balanceOf(bob), 0);

        assertFalse(wNftId1_bob == wNftId2_bob);
    }

    function test_acceptWithdrawal() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId1_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId1_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);

        uint256 wNftId1_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        uint256 wNftId_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 200 * 10 ** 18);

        // ### ACT ###
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId1_alice, 40 * 10 ** 18);
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId_bob, 160 * 10 ** 18);

        // non existing dNftId
        uint256 wNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_nonExistent));
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId_nonExistent, 50 * 10 ** 18);

        // ### ASSERT ###
        PendingPool pendingPool = PendingPool(lpd.pendingPool);

        WithdrawalNftDetails memory withdrawalNftDetails_bob = pendingPool.trancheWithdrawalNftDetails(wNftId_bob);
        assertEq(withdrawalNftDetails_bob.sharesAmount, 40 * 10 ** 18);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId1_alice));
        assertEq(pendingPool.ownerOf(wNftId1_alice), address(0));

        uint256 dNftId2_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId2_alice, 40 * 10 ** 6);
        uint256 wNftId2_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 20 * 10 ** 18);
        assertFalse(wNftId1_alice == wNftId2_alice);
    }

    function test_depositFirstLossCapital() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

        // ### ACT ###
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 350 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), ILendingPool(lpd.lendingPool).totalSupply());
    }

    function test_withdrawFirstLossCapital() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsNotStopped.selector));
        _withdrawFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 20 * 10 ** 6, poolFundsManagerAccount);

        _stop(poolManagerAccount, lpd.lendingPool);

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.WithdrawAmountCantBeGreaterThanFirstLostCapital.selector, 61 * 10 ** 6, 60 * 10 ** 6
            )
        );
        _withdrawFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 61 * 10 ** 6, poolFundsManagerAccount);
        _withdrawFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 20 * 10 ** 6, poolFundsManagerAccount);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(poolFundsManagerAccount), 20 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 330 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), ILendingPool(lpd.lendingPool).totalSupply());
    }

    function test_drawFunds() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 50 * 10 ** 6);

        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.DrawAmountCantBeGreaterThanAvailableAmount.selector, 341 * 10 ** 6, 340 * 10 ** 6
            )
        );
        _drawFunds(lpd.lendingPool, 341 * 10 ** 6);
        _drawFunds(lpd.lendingPool, 200 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 140 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(poolFundsManagerAccount), 200 * 10 ** 6);
        assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
        assertEq(ILendingPool(lpd.lendingPool).getUserOwedAmount(), 200 * 10 ** 6);
    }

    function test_repayOwedFunds_noFees() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

        uint256 owedAmount = 200 * 10 ** 6;
        _drawFunds(lpd.lendingPool, owedAmount);

        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        deal(address(mockUsdc), poolFundsManagerAccount, 300 * 10 ** 6, true);
        vm.startPrank(poolFundsManagerAccount);
        mockUsdc.approve(address(lendingPoolManager), 300 * 10 ** 6);

        // ### ACT ###

        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.RepayAmountCantBeGreaterThanOwedAmount.selector, owedAmount + 1, owedAmount
            )
        );
        lendingPoolManager.repayOwedFunds(lpd.lendingPool, owedAmount + 1, poolFundsManagerAccount);

        lendingPoolManager.repayOwedFunds(lpd.lendingPool, 100 * 10 ** 6, poolFundsManagerAccount);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 190 * 10 ** 6);
        assertEq(ILendingPool(lpd.lendingPool).getUserOwedAmount(), 100 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(poolFundsManagerAccount), 200 * 10 ** 6);
        assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
    }

    function test_repayOwedFunds_repayIncludingFees() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice = 200 * 10 ** 6;
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, requestDepositAmount_alice);

        _drawFunds(lpd.lendingPool, 100 * 10 ** 6);

        vm.prank(address(clearingCoordinator));
        ILendingPool(lpd.lendingPool).applyInterests(0);

        // should be 100450000
        uint256 userOwedAmount = ILendingPool(lpd.lendingPool).getUserOwedAmount();
        // should be 50000
        uint256 feesOwedAmount = ILendingPool(lpd.lendingPool).getFeesOwedAmount();

        uint256 usdcBefore = mockUsdc.balanceOf(lpd.lendingPool);

        // ### ACT ###
        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd.lendingPool, feesOwedAmount / 2);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), usdcBefore);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).getFeesOwedAmount(), feesOwedAmount / 2, 1);
        assertEq(ILendingPool(lpd.lendingPool).getUserOwedAmount(), userOwedAmount);

        // ### ACT ###
        _repayOwedFunds(
            poolFundsManagerAccount, poolFundsManagerAccount, lpd.lendingPool, feesOwedAmount / 2 + userOwedAmount / 2
        );

        // ### ASSERT ###
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), usdcBefore + userOwedAmount / 2, 1);
        assertEq(ILendingPool(lpd.lendingPool).getFeesOwedAmount(), 0);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).getUserOwedAmount(), userOwedAmount / 2, 1);

        // ### ACT ###
        _repayOwedFunds(
            poolFundsManagerAccount,
            poolFundsManagerAccount,
            lpd.lendingPool,
            ILendingPool(lpd.lendingPool).getUserOwedAmount()
        );

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), usdcBefore + userOwedAmount);
        assertEq(ILendingPool(lpd.lendingPool).getFeesOwedAmount(), 0);
        assertEq(ILendingPool(lpd.lendingPool).getUserOwedAmount(), 0);
    }

    function test_forceImmediateWithdrawal() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);

        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, alice, 50 * 10 ** 18, 40 * 10 ** 18)
        );
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, lpd.tranches[0], alice, 50 * 10 ** 18);
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, lpd.tranches[0], alice, 40 * 10 ** 18);
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, lpd.tranches[1], bob, 200 * 10 ** 18);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 50 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(alice), 40 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(bob), 200 * 10 ** 6);
    }

    function test_batchForceWithdrawals() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);

        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

        // ### ACT ###
        ForceWithdrawalInput[] memory input1 = new ForceWithdrawalInput[](2);
        uint256 requestWithdrawalSharesAmount_alice = 40 * 10 ** 18;
        input1[0] = ForceWithdrawalInput(lpd.tranches[0], alice, requestWithdrawalSharesAmount_alice);
        uint256 requestWithdrawalSharesAmount_bob = 200 * 10 ** 18;
        input1[1] = ForceWithdrawalInput(lpd.tranches[1], bob, requestWithdrawalSharesAmount_bob);

        uint256[] memory result = _batchForceWithdrawals(poolManagerAccount, lpd.lendingPool, input1);
        uint256 wNftId_alice = result[0];
        uint256 wNftId_bob = result[1];

        // request more assets to withdraw than user has in its balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.InsufficientSharesBalance.selector,
                bob,
                lpd.lendingPool,
                lpd.tranches[1],
                50 * 10 ** 18,
                51 * 10 ** 18
            )
        );
        ForceWithdrawalInput[] memory input2 = new ForceWithdrawalInput[](1);
        input2[0] = ForceWithdrawalInput(lpd.tranches[1], bob, 51 * 10 ** 18);
        _batchForceWithdrawals(poolManagerAccount, lpd.lendingPool, input2);

        // ### ASSERT ###
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertEq(lendingPool.totalSupply(), acceptDepositAmount_alice + acceptedDepositAmount_bob);
        assertEq(ILendingPoolTranche(lpd.tranches[0]).totalSupply(), acceptDepositAmount_alice * 10 ** 12);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).totalSupply(), acceptedDepositAmount_bob * 10 ** 12);

        assertEq(ILendingPoolTranche(lpd.tranches[0]).balanceOf(lpd.pendingPool), requestWithdrawalSharesAmount_alice);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(lpd.pendingPool), requestWithdrawalSharesAmount_bob);

        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        assertEq(pendingPool.ownerOf(wNftId_alice), alice);
        WithdrawalNftDetails memory withdrawalNftDetails_alice = pendingPool.trancheWithdrawalNftDetails(wNftId_alice);
        assertEq(withdrawalNftDetails_alice.sharesAmount, requestWithdrawalSharesAmount_alice);
        assertTrue(withdrawalNftDetails_alice.requestedFrom == RequestedFrom.SYSTEM);

        assertEq(pendingPool.ownerOf(wNftId_bob), bob);
        WithdrawalNftDetails memory withdrawalNftDetails_bob = pendingPool.trancheWithdrawalNftDetails(wNftId_bob);
        assertEq(withdrawalNftDetails_bob.sharesAmount, requestWithdrawalSharesAmount_bob);
        assertTrue(withdrawalNftDetails_bob.requestedFrom == RequestedFrom.SYSTEM);
    }

    function test_stop() external {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);
        uint256 dNftId_carol = _requestDeposit(carol, lpd.lendingPool, lpd.tranches[2], 10 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);

        _drawFunds(lpd.lendingPool, 200 * 10 ** 6);

        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 50 * 10 ** 6);

        // ### ACT / ASSERT ###

        // stop without repaying full owed amount
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.UserOwedAmountIsGreaterThanZero.selector, 200 * 10 ** 6));
        _stop(poolManagerAccount, lpd.lendingPool);

        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

        _stop(poolManagerAccount, lpd.lendingPool);

        _withdrawFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, 50 * 10 ** 6, lendingPoolAdminAccount);

        // TODO: w
        assertEq(mockUsdc.balanceOf(lendingPoolAdminAccount), 50 * 10 ** 6);

        // request deposit after stop - not allowed
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 10 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 10 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 10 * 10 ** 6, "");
        vm.stopPrank();

        // deposit first lost capital after stop - not allowed
        vm.startPrank(poolFundsManagerAccount);
        deal(address(mockUsdc), poolFundsManagerAccount, 10 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 10 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        lendingPoolManager.depositFirstLossCapital(lpd.lendingPool, 10 * 10 ** 6);
        vm.stopPrank();

        // draw funds after stop - even though balance is zero not allowed
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        _drawFunds(lpd.lendingPool, 10 * 10 ** 6);

        // accept deposit after stop - not allowed
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        _acceptDepositRequest(lpd.lendingPool, dNftId_carol, 10 * 10 ** 6);

        // check tranches interest rate is zero
        PoolConfiguration memory poolConfiguration = ILendingPool(lpd.lendingPool).poolConfiguration();
        for (uint256 i = 0; i < poolConfiguration.tranches.length; ++i) {
            assertEq(poolConfiguration.tranches[i].interestRate, 0);
        }
    }

    function test_getUserAvailableBalance() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 requestDepositAmount_alice0 = 100 * 10 ** 6;
        uint256 requestDepositAmount_alice1 = 200 * 10 ** 6;
        uint256 requestDepositAmount_alice2 = 300 * 10 ** 6;
        uint256 dNftId_alice0 = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice0);
        uint256 dNftId_alice1 = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_alice1);
        uint256 dNftId_alice2 = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[2], requestDepositAmount_alice2);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice0, requestDepositAmount_alice0);
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice1, requestDepositAmount_alice1);
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice2, requestDepositAmount_alice2);

        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, requestDepositAmount_bob);

        // ### ACT ###
        uint256 userAvailableBalance_alice = ILendingPool(lpd.lendingPool).getUserBalance(alice);
        uint256 userAvailableBalance_bob = ILendingPool(lpd.lendingPool).getUserBalance(bob);

        // ### ASSERT ###
        assertEq(
            userAvailableBalance_alice,
            requestDepositAmount_alice0 + requestDepositAmount_alice1 + requestDepositAmount_alice2
        );
        assertEq(userAvailableBalance_bob, requestDepositAmount_bob);
    }

    function test_getUserPendingDepositAmount() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // request depoists
        uint256 requestDepositAmount_alice0 = 100 * 10 ** 6;
        uint256 requestDepositAmount_alice1 = 200 * 10 ** 6;
        uint256 requestDepositAmount_alice2 = 300 * 10 ** 6;
        uint256 dNftId_alice0 = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice0);
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_alice1);
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[2], requestDepositAmount_alice2);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

        // request withdrawals
        _acceptDepositRequest(lpd.lendingPool, dNftId_alice0, requestDepositAmount_alice0);

        uint256 requestWithdrawalSharesAmount_alice = ILendingPoolTranche(lpd.tranches[0]).balanceOf(alice);
        _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], requestWithdrawalSharesAmount_alice);

        // ### ACT ###
        skip(6 days + 1);
        uint256 epochId = systemVariables.getCurrentEpochNumber();
        uint256 userPendingDepositBalance_alice =
            IPendingPool(lpd.pendingPool).getUserPendingDepositAmount(alice, epochId);
        uint256 userPendingDepositBalance_bob = IPendingPool(lpd.pendingPool).getUserPendingDepositAmount(bob, epochId);

        // ### ASSERT ###
        assertEq(userPendingDepositBalance_alice, requestDepositAmount_alice1 + requestDepositAmount_alice2);
        assertEq(userPendingDepositBalance_bob, requestDepositAmount_bob);
    }

    function test_updateConfig() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ### ACT ###
        vm.startPrank(poolManagerAccount);

        lendingPoolManager.updateMinimumDepositAmount(lpd.lendingPool, lpd.tranches[0], 1000 * 1e6);
        lendingPoolManager.updateMaximumDepositAmount(lpd.lendingPool, lpd.tranches[0], 200_000 * 1e6);
        uint256[] memory ratios = new uint256[](3);
        ratios[0] = 15_00;
        ratios[1] = 25_00;
        ratios[2] = 60_00;
        lendingPoolManager.updateTrancheDesiredRatios(lpd.lendingPool, ratios);
        lendingPoolManager.updateDesiredDrawAmount(lpd.lendingPool, 400_000 * 1e6);

        // wrong ratios
        uint256[] memory wrongRatios = new uint256[](3);
        wrongRatios[0] = 15_00;
        wrongRatios[1] = 25_00;
        wrongRatios[2] = 50_00;
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPool.PoolConfigurationIsIncorrect.selector, "invalid tranche ratio sum")
        );
        lendingPoolManager.updateTrancheDesiredRatios(lpd.lendingPool, wrongRatios);

        uint256 updatedTranche1InterestRate = 1000000000000000;
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], updatedTranche1InterestRate);

        vm.stopPrank();

        // ### ASSERT ###
        ILendingPool lendingPool = ILendingPool(address(lpd.lendingPool));
        PoolConfiguration memory poolConfiguration = lendingPool.poolConfiguration();

        assertEq(poolConfiguration.desiredDrawAmount, 400_000 * 1e6);

        assertEq(poolConfiguration.tranches[0].ratio, 15_00);
        assertEq(poolConfiguration.tranches[0].interestRate, 2500000000000000);
        assertEq(poolConfiguration.tranches[0].minDepositAmount, 1000 * 1e6);
        assertEq(poolConfiguration.tranches[0].maxDepositAmount, 200_000 * 1e6);

        assertEq(poolConfiguration.tranches[1].ratio, 25_00);
        assertEq(poolConfiguration.tranches[1].interestRate, 2000000000000000);
        assertEq(poolConfiguration.tranches[1].minDepositAmount, 10 * 1e6);
        assertEq(poolConfiguration.tranches[1].maxDepositAmount, 1_000_000 * 1e6);

        assertEq(poolConfiguration.tranches[2].ratio, 60_00);
        assertEq(poolConfiguration.tranches[2].interestRate, 1500000000000000);
        assertEq(poolConfiguration.tranches[2].minDepositAmount, 10 * 1e6);
        assertEq(poolConfiguration.tranches[2].maxDepositAmount, 1_000_000 * 1e6);

        // update interest rate epoch delay
        uint256 interestRateEpochDelay = systemVariables.defaultTrancheInterestChangeEpochDelay();
        skip(7 days * (interestRateEpochDelay - 1));

        poolConfiguration = lendingPool.poolConfiguration();
        assertEq(poolConfiguration.tranches[1].interestRate, 2000000000000000);

        skip(7 days);

        poolConfiguration = lendingPool.poolConfiguration();
        assertEq(poolConfiguration.tranches[1].interestRate, updatedTranche1InterestRate);
    }

    function test_forceCancelDepositRequest() external {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        // ### ACT ###
        vm.prank(poolManagerAccount);
        lendingPoolManager.forceCancelDepositRequest(lpd.lendingPool, dNftId_alice);

        vm.prank(poolManagerAccount);
        lendingPoolManager.forceCancelDepositRequest(lpd.lendingPool, dNftId_bob);

        // ### ASSERT ###
        PendingPool pendingPool = PendingPool(lpd.pendingPool);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_alice));
        assertEq(pendingPool.ownerOf(dNftId_alice), address(0));
        assertEq(mockUsdc.balanceOf(alice), 100 * 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_bob));
        assertEq(pendingPool.ownerOf(dNftId_bob), address(0));
        assertEq(mockUsdc.balanceOf(bob), 250 * 10 ** 6);
    }

    function test_forceCancelWithdrawRequest() external {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 250 * 10 ** 6);

        uint256 wNftId_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        uint256 wNftId1_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 200 * 10 ** 18);

        // ### ACT ###
        vm.prank(poolManagerAccount);
        lendingPoolManager.forceCancelWithdrawalRequest(lpd.lendingPool, wNftId_alice);

        vm.prank(poolManagerAccount);
        lendingPoolManager.forceCancelWithdrawalRequest(lpd.lendingPool, wNftId1_bob);

        // ### ASSERT ###
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_alice));
        assertEq(pendingPool.ownerOf(wNftId_alice), address(0));
        assertEq(mockUsdc.balanceOf(alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId1_bob));
        assertEq(pendingPool.ownerOf(wNftId1_bob), address(0));
        assertEq(mockUsdc.balanceOf(bob), 0);
    }

    function test_incorrectMinimumTrancheCount() public {
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreatorAccount);

        uint256 targetExcessLiquidityPercentage = 50_000 * 1e6;
        uint256 desiredDrawAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](0);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );

        vm.startPrank(lendingPoolCreatorAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.PoolConfigurationIsIncorrect.selector, "tranche count less than minimum"
            )
        );
        lendingPoolManager.createPool(createPoolConfig);
        vm.stopPrank();
    }

    function test_incorrectMaximumTrancheCount() public {
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreatorAccount);

        uint256 minDepositAmount = 500 * 1e6;
        uint256 maxDepositAmount = 100_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 50_000 * 1e6;
        uint256 desiredDrawAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](4);
        createTrancheConfig[0] = CreateTrancheConfig(10_00, 5_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(20_00, 4_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[2] = CreateTrancheConfig(30_00, 3_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[3] = CreateTrancheConfig(40_00, 3_00, minDepositAmount, maxDepositAmount);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );

        vm.startPrank(lendingPoolCreatorAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.PoolConfigurationIsIncorrect.selector, "tranche count more than maximum"
            )
        );
        lendingPoolManager.createPool(createPoolConfig);
        vm.stopPrank();
    }

    function test_applyInterests_onlyClearingCoordinator() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ### ACT ###
        vm.expectRevert(abi.encodeWithSelector(ILendingPoolErrors.OnlyClearingCoordinator.selector));
        ILendingPool(lpd.lendingPool).applyInterests(1);
    }

    function test_requestDepositAmountOutsideAllowedRange() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        vm.startPrank(poolManagerAccount);

        lendingPoolManager.updateMinimumDepositAmount(lpd.lendingPool, lpd.tranches[0], 100 * 1e6);
        lendingPoolManager.updateMaximumDepositAmount(lpd.lendingPool, lpd.tranches[0], 200 * 1e6);

        lendingPoolManager.updateMinimumDepositAmount(lpd.lendingPool, lpd.tranches[1], 1_000 * 1e6);
        lendingPoolManager.updateMaximumDepositAmount(lpd.lendingPool, lpd.tranches[1], 10_000 * 1e6);

        lendingPoolManager.updateMinimumDepositAmount(lpd.lendingPool, lpd.tranches[2], 50 * 1e6);
        lendingPoolManager.updateMaximumDepositAmount(lpd.lendingPool, lpd.tranches[2], 500 * 1e6);

        vm.stopPrank();

        // ### ACT / ASSERT ###
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 150 * 1e6);

        deal(address(mockUsdc), alice, 51 * 1e6, true);
        vm.startPrank(alice);
        mockUsdc.approve(address(lendingPoolManager), 51 * 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.RequestDepositAmountMoreThanMaximumAllowed.selector,
                lpd.lendingPool,
                lpd.tranches[0],
                200 * 1e6,
                201 * 1e6,
                51 * 1e6
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 51 * 1e6, "");
        vm.stopPrank();

        deal(address(mockUsdc), bob, 500 * 1e6, true);
        vm.startPrank(bob);
        mockUsdc.approve(address(lendingPoolManager), 500 * 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.RequestDepositAmountLessThanMinimumAllowed.selector,
                lpd.lendingPool,
                lpd.tranches[1],
                1_000 * 1e6,
                500 * 1e6,
                500 * 1e6
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 500 * 1e6, "");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AmountShouldBeGreaterThanZero.selector));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 0, "");
        vm.stopPrank();
    }

    function test_mockExchange_swap() public {
        // ARRANGE
        uint256 rate = 30; // 0.003 * 100_00
        (address exchange, address inToken) = _createMockExchange(rate);
        deal(address(inToken), alice, 12_000 ether);

        // ACT
        vm.startPrank(alice);
        IERC20(inToken).approve(exchange, 12_000 ether);
        uint256 out = MockExchange(exchange).swap(12_000 ether, alice);
        vm.stopPrank();

        // ASSERT
        assertEq(out, 12_000 * 1e6 * 0.003);
        assertEq(out, 36000000);
        assertEq(IERC20(mockUsdc).balanceOf(alice), out);
    }

    function test_swapper_invalidController() public {
        vm.expectRevert(abi.encodeWithSelector(ConfigurationAddressZero.selector));
        new Swapper(IKasuController(address(0)));
    }

    function test_swapper_setAllowList_unauthorized() public {
        // ARRANGE
        address[] memory addresses = ArraysUtil.toArray(address(0x1));
        bool[] memory values = ArraysUtil.toArray(true);

        // ACT & ASSERT
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        swapper.updateExchangeAllowlist(addresses, values);
        vm.stopPrank();
    }

    function test_swapper_setAllowList() public {
        // ACT
        vm.startPrank(admin);
        swapper.updateExchangeAllowlist(ArraysUtil.toArray(address(lendingPoolManager)), ArraysUtil.toArray(true));
        vm.stopPrank();

        // ASSERT
        assertTrue(swapper.isExchangeAllowed(address(lendingPoolManager)));
    }

    function test_swapper_exchangeNotContract() public {
        // ARRANGE
        address[] memory addresses = ArraysUtil.toArray(address(0x1));
        bool[] memory values = ArraysUtil.toArray(true);

        // ACT & ASSERT
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(AddressNotContract.selector, addresses[0]));
        swapper.updateExchangeAllowlist(addresses, values);
        vm.stopPrank();
    }

    function test_swapper_exchangeNotAllowed() public {
        // ARRANGE
        (address exchange, address inToken) = _createMockExchange(30);
        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        swapInfo[0] = SwapInfo(
            exchange,
            inToken,
            abi.encodeWithSelector(MockExchange(exchange).swap.selector, 12_000 ether, address(lendingPoolManager))
        );

        address[] memory inTokens = ArraysUtil.toArray(inToken);

        // ACT & ASSERT
        vm.startPrank(address(lendingPoolManager));
        vm.expectRevert(abi.encodeWithSelector(ExchangeNotAllowed.selector, exchange));
        swapper.swap(inTokens, swapInfo, address(0x1), address(0x1));
        vm.stopPrank();
    }

    function test_swapper_swap_unauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_SWAPPER)
        );
        vm.startPrank(alice);
        swapper.swap(new address[](0), new SwapInfo[](0), address(0), address(0));
        vm.stopPrank();
    }

    function test_swapper_swap_noSwapInfo() public {
        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        address[] memory tokens = ArraysUtil.toArray(address(0x1));

        vm.startPrank(address(lendingPoolManager));

        vm.expectRevert(abi.encodeWithSelector(InvalidSwapData.selector));
        swapper.swap(tokens, new SwapInfo[](0), address(0x1), address(0x1));

        vm.expectRevert(abi.encodeWithSelector(InvalidSwapData.selector));
        swapper.swap(new address[](0), swapInfo, address(0x1), address(0x1));

        vm.expectRevert(abi.encodeWithSelector(InvalidSwapData.selector));
        swapper.swap(tokens, swapInfo, address(0), address(0x1));

        vm.expectRevert(abi.encodeWithSelector(InvalidSwapData.selector));
        swapper.swap(tokens, swapInfo, address(0x1), address(0));

        vm.stopPrank();
    }

    function test_requestDeposit_swap() public {
        // ARRANGE
        uint256 usdcDepositAmount = 36000000;
        uint256 rate = 30; // 0.003 * 100_00
        (address exchange, address inToken) = _createMockExchange(rate);
        deal(address(inToken), alice, 13_500 ether);
        deal(alice, 12 ether);

        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // Alice has 13_500, sends 13_000, 12_500 gets swapped, 12_000 deposited
        // 500 should be returned in inToken
        // 500 (* 0.003 * 1e6) should be returned in USDC
        SwapInfo[] memory swapInfo = new SwapInfo[](1);
        swapInfo[0] = SwapInfo(
            exchange,
            inToken,
            abi.encodeWithSelector(MockExchange(exchange).swap.selector, 12_500 ether, address(lendingPoolManager))
        );

        SwapDepositBag memory bag = SwapDepositBag({
            inTokens: ArraysUtil.toArray(inToken),
            inAmounts: ArraysUtil.toArray(13_000 ether),
            swapInfo: swapInfo
        });

        vm.startPrank(admin);
        swapper.updateExchangeAllowlist(ArraysUtil.toArray(exchange), ArraysUtil.toArray(true));
        vm.stopPrank();

        // ACT
        vm.startPrank(alice);
        IERC20(inToken).approve(address(lendingPoolManager), 13_000 ether);

        // 12 WETH should be returned
        uint256 depositId = lendingPoolManager.requestDeposit{value: 12 ether}(
            lpd.lendingPool, lpd.tranches[0], usdcDepositAmount, abi.encode(bag)
        );
        vm.stopPrank();

        DepositNftDetails memory depositNFT = IPendingPool(lpd.pendingPool).trancheDepositNftDetails(depositId);

        // ASSERT
        assertEq(weth.balanceOf(alice), 12 ether); // 12 ETH was deposited into WETH
        assertEq(IERC20(inToken).balanceOf(alice), 1000 ether); // 500 remained on the wallet and 500 was returned
        assertEq(depositNFT.assetAmount, usdcDepositAmount); // deposited
        assertEq(IERC20(mockUsdc).balanceOf(alice), 500 * 0.003 * 1e6); // swapped, but not deposited
    }
}
