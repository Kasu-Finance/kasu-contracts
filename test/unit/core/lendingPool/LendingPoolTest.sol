// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "./utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../../../../src/core/interfaces/lendingPool/IPendingPool.sol";

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

    function test_cancelDeposit() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        address lendingPoolAddress = lendingPoolDeployment.lendingPool;
        address juniorTrancheAddress = lendingPoolDeployment.tranches[0];
        address mezzoTrancheAddress = lendingPoolDeployment.tranches[1];

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice =
            _requestDeposit(alice, lendingPoolAddress, juniorTrancheAddress, requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, requestDepositAmount_bob);

        // ### ACT ###
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, dNftId_alice));
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId_alice);

        _cancelDepositRequest(alice, lendingPoolAddress, dNftId_alice);
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId_bob);

        // non existing dNftId
        uint256 dNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_nonExistent));
        _cancelDepositRequest(bob, lendingPoolAddress, dNftId_nonExistent);

        // ### ASSERT ###
        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);

        // dNft burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_alice));
        assertEq(pendingPool.ownerOf(dNftId_alice), address(0));

        // dNft burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_bob));
        assertEq(pendingPool.ownerOf(dNftId_bob), address(0));
    }

    function test_acceptDeposit() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lendingPoolDeployment = _createDefaultLendingPool();
        address lendingPoolAddress = lendingPoolDeployment.lendingPool;
        address juniorTrancheAddress = lendingPoolDeployment.tranches[0];
        address mezzoTrancheAddress = lendingPoolDeployment.tranches[1];

        uint256 requestDepositAmount_alice = 100 * 10 ** 6;
        uint256 dNftId_alice =
            _requestDeposit(alice, lendingPoolAddress, juniorTrancheAddress, requestDepositAmount_alice);

        uint256 requestDepositAmount_bob = 250 * 10 ** 6;
        uint256 dNftId_bob = _requestDeposit(bob, lendingPoolAddress, mezzoTrancheAddress, requestDepositAmount_bob);

        // ### ACT ###
        uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
        _acceptDepositRequest(lendingPoolAddress, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDepositRequest(lendingPoolAddress, dNftId_bob, acceptedDepositAmount_bob);

        // non existing dNftId
        uint256 dNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_nonExistent));
        _acceptDepositRequest(lendingPoolAddress, dNftId_nonExistent, acceptedDepositAmount_bob);

        // accept more assets than requests
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.TooManyAssetsRequested.selector, dNftId_alice, 60 * 10 ** 6, 61 * 10 ** 6
            )
        );
        _acceptDepositRequest(lendingPoolAddress, dNftId_alice, 61 * 10 ** 6);

        // ### ASSERT ###
        ILendingPool lendingPool = ILendingPool(lendingPoolAddress);
        assertEq(lendingPool.totalSupply(), acceptDepositAmount_alice + acceptedDepositAmount_bob);
        assertEq(ILendingPoolTranche(juniorTrancheAddress).totalSupply(), acceptDepositAmount_alice * 10 ** 12);
        assertEq(ILendingPoolTranche(mezzoTrancheAddress).totalSupply(), acceptedDepositAmount_bob * 10 ** 12);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(mockUsdc.balanceOf(address(pendingPool)), requestDepositAmount_alice - acceptDepositAmount_alice);

        assertEq(pendingPool.ownerOf(dNftId_alice), alice);
        DepositNftDetails memory depositNftDetails_alice = pendingPool.trancheDepositNftDetails(dNftId_alice);
        assertEq(depositNftDetails_alice.assetAmount, requestDepositAmount_alice - acceptDepositAmount_alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_bob));
        assertEq(pendingPool.ownerOf(dNftId_bob), address(0));
    }

    function test_requestWithdrawal() public {
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
        uint256 requestWithdrawalSharesAmount_alice = 40 * 10 ** 18;
        uint256 wNftId_alice =
            _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], requestWithdrawalSharesAmount_alice);

        uint256 requestWithdrawalSharesAmount_bob = 200 * 10 ** 18;
        uint256 wNftId_bob =
            _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], requestWithdrawalSharesAmount_bob);

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

        assertEq(pendingPool.ownerOf(wNftId_bob), bob);
        WithdrawalNftDetails memory withdrawalNftDetails_bob = pendingPool.trancheWithdrawalNftDetails(wNftId_bob);
        assertEq(withdrawalNftDetails_bob.sharesAmount, requestWithdrawalSharesAmount_bob);
    }

    function test_cancelWithdrawalRequest() public {
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

        uint256 requestWithdrawalSharesAmount_alice = 40 * 10 ** 18;
        uint256 wNftId_alice =
            _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], requestWithdrawalSharesAmount_alice);

        uint256 requestWithdrawalSharesAmount_bob = 200 * 10 ** 18;
        uint256 wNftId_bob =
            _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], requestWithdrawalSharesAmount_bob);

        // ### ACT ###
        // incorrect owner
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, wNftId_alice));
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId_alice);

        _cancelWithdrawalRequest(alice, lpd.lendingPool, wNftId_alice);
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId_bob);

        // non existing dNftId
        uint256 wNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_nonExistent));
        _cancelWithdrawalRequest(bob, lpd.lendingPool, wNftId_nonExistent);

        // ### ASSERT ###
        // wNft burned
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_alice));
        assertEq(pendingPool.ownerOf(wNftId_alice), address(0));

        // wNft burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_bob));
        assertEq(pendingPool.ownerOf(wNftId_bob), address(0));
    }

    function test_acceptWithdrawal() public {
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

        uint256 requestWithdrawalSharesAmount_alice = 40 * 10 ** 18;
        uint256 wNftId_alice =
            _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], requestWithdrawalSharesAmount_alice);

        uint256 requestWithdrawalSharesAmount_bob = 200 * 10 ** 18;
        uint256 wNftId_bob =
            _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], requestWithdrawalSharesAmount_bob);

        // ### ACT ###
        uint256 acceptedWithdrawalSharesAmount_alice = 40 * 10 ** 18;
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId_alice, acceptedWithdrawalSharesAmount_alice);

        uint256 acceptedWithdrawalSharesAmount_bob = 160 * 10 ** 18;
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId_bob, acceptedWithdrawalSharesAmount_bob);

        // non existing dNftId
        uint256 wNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_nonExistent));
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId_nonExistent, acceptedWithdrawalSharesAmount_bob);

        // ### ASSERT ###
        PendingPool pendingPool = PendingPool(lpd.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId_alice), alice);
        WithdrawalNftDetails memory withdrawalNftDetails_bob = pendingPool.trancheWithdrawalNftDetails(wNftId_bob);
        assertEq(
            withdrawalNftDetails_bob.sharesAmount,
            requestWithdrawalSharesAmount_bob - acceptedWithdrawalSharesAmount_bob
        );

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, wNftId_alice));
        assertEq(pendingPool.ownerOf(wNftId_alice), address(0));
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
        _depositFirstLossCapital(lendingPoolLoanAdmin, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(lendingPoolLoanAdmin, lpd.lendingPool, 10 * 10 ** 6);

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

        _depositFirstLossCapital(lendingPoolLoanAdmin, lpd.lendingPool, 50 * 10 ** 6);
        _depositFirstLossCapital(lendingPoolLoanAdmin, lpd.lendingPool, 10 * 10 ** 6);

        // ### ACT ###
        _withdrawFirstLossCapital(lendingPoolLoanAdmin, lendingPoolLoanAdmin, lpd.lendingPool, 20 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lendingPoolLoanAdmin), 20 * 10 ** 6);
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

        _depositFirstLossCapital(lendingPoolLoanAdmin, lpd.lendingPool, 50 * 10 ** 6);

        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        // ### ACT ###
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.BorrowAmountCantBeGreaterThanAvailableAmount.selector, 341 * 10 ** 6, 340 * 10 ** 6
            )
        );
        _borrowLoan(lendingPoolLoanAdmin, lpd.lendingPool, 341 * 10 ** 6);
        _borrowLoan(lendingPoolLoanAdmin, lpd.lendingPool, 200 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 140 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lendingPoolLoanAdmin), 200 * 10 ** 6);
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
        _borrowLoan(lendingPoolLoanAdmin, lpd.lendingPool, 200 * 10 ** 6);

        // ### ACT ###
        uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

        _repayLoan(lendingPoolLoanAdmin, lendingPoolLoanAdmin, lpd.lendingPool, 100 * 10 ** 6);

        // ### ASSERT ###
        assertEq(mockUsdc.balanceOf(lpd.lendingPool), 190 * 10 ** 6);
        assertEq(mockUsdc.balanceOf(lendingPoolLoanAdmin), 0);
        assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
    }
}
