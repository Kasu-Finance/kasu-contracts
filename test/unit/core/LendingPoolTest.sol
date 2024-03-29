// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "../../../src/core/lendingPool/LendingPoolStoppable.sol";
import "../../../src/shared/CommonErrors.sol";

contract LendingPoolTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_requestDeposit() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ACT
        uint256 dNftId1_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], 50 * 10 ** 6);

        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(true);

        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], 50 * 10 ** 6);

        // request deposit on junior tranche when no locking took place
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(
            abi.encodeWithSelector(IPendingPool.UserCanOnlyDepositInJuniorTrancheIfHeHasLockedRKsu.selector, bob)
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6);
        vm.stopPrank();

        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(false);

        // request deposit on user that is not allowed
        vm.startPrank(userNotAllowed);
        deal(address(mockUsdc), userNotAllowed, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(IKasuAllowList.UserNotInAllowList.selector, userNotAllowed));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6);
        vm.stopPrank();

        // request deposit on user that was allowed and now is disallowed
        vm.prank(admin);
        kasuAllowList.disallowUser(bob);
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 125 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 125 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(IKasuAllowList.UserNotInAllowList.selector, bob));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 125 * 10 ** 6);
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
        vm.expectRevert(abi.encodeWithSelector(NonTransferable.selector));
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

        address pendingPoolAddress = lendingPool.getPendingPool();
        assertEq(ILendingPoolTranche(lpd.tranches[0]).balanceOf(pendingPoolAddress), 40 * 10 ** 18);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(pendingPoolAddress), 200 * 10 ** 18);

        IPendingPool pendingPool = IPendingPool(pendingPoolAddress);
        assertEq(pendingPool.ownerOf(wNftId_alice), alice);
        WithdrawalNftDetails memory withdrawalNftDetails_alice = pendingPool.trancheWithdrawalNftDetails(wNftId_alice);
        assertEq(withdrawalNftDetails_alice.sharesAmount, 40 * 10 ** 18);

        assertEq(pendingPool.ownerOf(wNftId1_bob), bob);
        WithdrawalNftDetails memory withdrawalNftDetails_bob = pendingPool.trancheWithdrawalNftDetails(wNftId1_bob);
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
        uint256 wNftId_carol = _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input1)[0];

        // ### ACT ###
        // incorrect owner
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, wNftId_alice));
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId_alice);

        _cancelWithdrawalRequest(alice, lpd.lendingPool, wNftId_alice);
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId1_bob);

        // try to cancel forced withdrawal request
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.WithdrawalRequestIsForced.selector, carol, lpd.lendingPool, wNftId_carol
            )
        );
        _cancelWithdrawalRequest(carol, lpd.lendingPool, wNftId_carol);

        // non existing dNftId
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.WithdrawalRequestIsForced.selector, carol, lpd.lendingPool, wNftId_carol
            )
        );
        _cancelWithdrawalRequest(carol, lpd.lendingPool, wNftId_carol);

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
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

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

        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.WithdrawAmountCantBeGreaterThanFirstLostCapital.selector, 61 * 10 ** 6, 60 * 10 ** 6
            )
        );
        _withdrawFirstLossCapital(
            lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 61 * 10 ** 6
        );
        _withdrawFirstLossCapital(
            lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 20 * 10 ** 6
        );

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lendingPoolLoanManagerAccount), 20 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 330 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), ILendingPool(lpd.lendingPool).totalSupply());
    }

    function test_borrowLoan() public {
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

        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);

        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.BorrowAmountCantBeGreaterThanAvailableAmount.selector, 341 * 10 ** 6, 340 * 10 ** 6
            )
        );
        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, 341 * 10 ** 6);
        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 140 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lendingPoolLoanManagerAccount), 200 * 10 ** 6);
        assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
    }

    function test_repayLoan() public {
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
        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

        // ### ACT ###
        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        _repayLoan(lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 100 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 190 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lendingPoolLoanManagerAccount), 0);
        assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
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
        _forceImmediateWithdrawal(lendingPoolManagerAccount, lpd.lendingPool, lpd.tranches[0], alice, 50 * 10 ** 18);
        _forceImmediateWithdrawal(lendingPoolManagerAccount, lpd.lendingPool, lpd.tranches[0], alice, 40 * 10 ** 18);
        _forceImmediateWithdrawal(lendingPoolManagerAccount, lpd.lendingPool, lpd.tranches[1], bob, 200 * 10 ** 18);

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

        uint256[] memory result = _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input1);
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
        _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input2);

        // ### ASSERT ###
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertEq(lendingPool.totalSupply(), acceptDepositAmount_alice + acceptedDepositAmount_bob);
        assertEq(ILendingPoolTranche(lpd.tranches[0]).totalSupply(), acceptDepositAmount_alice * 10 ** 12);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).totalSupply(), acceptedDepositAmount_bob * 10 ** 12);

        address pendingPoolAddress = lendingPool.getPendingPool();
        assertEq(
            ILendingPoolTranche(lpd.tranches[0]).balanceOf(pendingPoolAddress), requestWithdrawalSharesAmount_alice
        );
        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(pendingPoolAddress), requestWithdrawalSharesAmount_bob);

        IPendingPool pendingPool = IPendingPool(pendingPoolAddress);
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

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);

        // ### ACT / ASSERT ###

        // stop without repaying all borrowed loan
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.BorrowedAmountIsGreaterThanZero.selector, 200 * 10 ** 6));
        _stop(lendingPoolManagerAccount, lpd.lendingPool, lendingPoolAdminAccount);

        _repayLoan(lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

        _stop(lendingPoolManagerAccount, lpd.lendingPool, lendingPoolAdminAccount);
        assertEq(mockUsdc.balanceOf(lendingPoolAdminAccount), 50 * 10 ** 6);

        // request deposit after stop - not allowed
        vm.startPrank(bob);
        deal(address(mockUsdc), bob, 10 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 10 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 10 * 10 ** 6);
        vm.stopPrank();

        // deposit first lost capital after stop - not allowed
        vm.startPrank(lendingPoolLoanManagerAccount);
        deal(address(mockUsdc), lendingPoolLoanManagerAccount, 10 * 10 ** 6, true);
        mockUsdc.approve(address(lendingPoolManager), 10 * 10 ** 6);
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        lendingPoolManager.depositFirstLossCapital(lpd.lendingPool, 10 * 10 ** 6);
        vm.stopPrank();

        // borrow loan after stop - even though balance is zero not allowed
        vm.expectRevert(abi.encodeWithSelector(ILendingPool.LendingPoolIsStopped.selector));
        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

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
        vm.startPrank(lendingPoolManagerAccount);

        lendingPoolManager.updateMinimumDepositAmount(lpd.lendingPool, lpd.tranches[0], 1000 * 1e6);
        lendingPoolManager.updateMaximumDepositAmount(lpd.lendingPool, lpd.tranches[0], 200_000 * 1e6);
        uint256[] memory ratios = new uint256[](3);
        ratios[0] = 15_00;
        ratios[1] = 25_00;
        ratios[2] = 60_00;
        lendingPoolManager.updateTrancheDesiredRatios(lpd.lendingPool, ratios);
        lendingPoolManager.updateTotalDesiredLoanAmount(lpd.lendingPool, 400_000 * 1e6);

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

        assertEq(poolConfiguration.totalDesiredLoanAmount, 400_000 * 1e6);

        assertEq(poolConfiguration.tranches[0].ratio, 15_00);
        assertEq(poolConfiguration.tranches[0].interestRate, 2500000000000000);
        assertEq(poolConfiguration.tranches[0].minDepositAmount, 1000 * 1e6);
        assertEq(poolConfiguration.tranches[0].maxDepositAmount, 200_000 * 1e6);

        assertEq(poolConfiguration.tranches[1].ratio, 25_00);
        assertEq(poolConfiguration.tranches[1].interestRate, 2000000000000000);
        assertEq(poolConfiguration.tranches[1].minDepositAmount, 500 * 1e6);
        assertEq(poolConfiguration.tranches[1].maxDepositAmount, 100_000 * 1e6);

        assertEq(poolConfiguration.tranches[2].ratio, 60_00);
        assertEq(poolConfiguration.tranches[2].interestRate, 1500000000000000);
        assertEq(poolConfiguration.tranches[2].minDepositAmount, 500 * 1e6);
        assertEq(poolConfiguration.tranches[2].maxDepositAmount, 100_000 * 1e6);

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
        vm.prank(lendingPoolManagerAccount);
        lendingPoolManager.forceCancelDepositRequest(lpd.lendingPool, dNftId_alice);

        vm.prank(lendingPoolManagerAccount);
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
        vm.prank(lendingPoolManagerAccount);
        lendingPoolManager.forceCancelWithdrawalRequest(lpd.lendingPool, wNftId_alice);

        vm.prank(lendingPoolManagerAccount);
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
        uint256 totalDesiredLoanAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](0);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            lendingPoolLoanManagerAccount,
            totalDesiredLoanAmount
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
        uint256 totalDesiredLoanAmount = 600_000 * 1e6;
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
            lendingPoolLoanManagerAccount,
            totalDesiredLoanAmount
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
}
