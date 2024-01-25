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
        _acceptDeposit(alice, lendingPoolAddress, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDeposit(bob, lendingPoolAddress, dNftId_bob, acceptedDepositAmount_bob);

        // non existing dNftId
        uint256 dNftId_nonExistent = 888;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, dNftId_nonExistent));
        _acceptDeposit(bob, lendingPoolAddress, dNftId_nonExistent, acceptedDepositAmount_bob);

        // incorrect owner
        vm.expectRevert(abi.encodeWithSelector(IPendingPool.UserIsNotOwnerOfNFT.selector, bob, dNftId_alice));
        _acceptDeposit(bob, lendingPoolAddress, dNftId_alice, acceptedDepositAmount_bob);

        // accept more assets than requests
        vm.expectRevert(
            abi.encodeWithSelector(
                IPendingPool.TooManyAssetsRequested.selector, dNftId_alice, 60 * 10 ** 6, 61 * 10 ** 6
            )
        );
        _acceptDeposit(alice, lendingPoolAddress, dNftId_alice, 61 * 10 ** 6);

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
        _acceptDeposit(alice, lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

        uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
        _acceptDeposit(bob, lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

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

    function test_acceptWithdrawal() public {}

    function test_cancelWithdrawalRequest() public {}
}
