// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import {LossDetails} from "../../../src/core/interfaces/lendingPool/ILendingPoolTrancheLoss.sol";
import "../../../src/core/lendingPool/LendingPoolStoppable.sol";
import "../../../src/shared/CommonErrors.sol";

contract LendingPoolLossTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_firstLossCapitalLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount);

        // ### ASSERT ###
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        assertEq(LendingPool(lpd.lendingPool).borrowedAmount(), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), 0);
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
    }

    function test_singleTrancheLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 3, lpd.tranches[0], totalUserDeposits);

        _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount);

        // ### ASSERT ###

        // assert lending pool
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        uint256 expectedBalanceLeft = firstLossCapitalAmount + totalUserDeposits - lossAmount;
        assertEq(LendingPool(lpd.lendingPool).borrowedAmount(), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[0]), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), expectedBalanceLeft);

        // assert tranche loss
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(1));
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).getLossDetails(1);
        assertEq(lossDetails.lossAmount, totalUserDeposits / 2);
        assertEq(lossDetails.usersCount, 3);
    }

    function test_multipleTrancheLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 trancheDeposits0 = 100_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 3, lpd.tranches[0], trancheDeposits0);

        uint256 trancheDeposits1 = 200_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 4, lpd.tranches[1], trancheDeposits1);

        uint256 trancheDeposits2 = 650_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 5, lpd.tranches[2], trancheDeposits2);

        uint256 borrowAmount = firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2;
        _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, borrowAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2 / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount);

        // ### ASSERT ###
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        uint256 expectedBalanceLeft =
            firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2 - lossAmount;
        assertEq(LendingPool(lpd.lendingPool).borrowedAmount(), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[0]), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[1]), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[2]), trancheDeposits2 / 2);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), expectedBalanceLeft);

        // assert tranche loss
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(1));
        LossDetails memory lossDetails0 = LendingPoolTranche(lpd.tranches[0]).getLossDetails(1);
        assertEq(lossDetails0.lossAmount, trancheDeposits0);
        assertEq(lossDetails0.usersCount, 3);

        assertTrue(LendingPoolTranche(lpd.tranches[1]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[1]).isLossMintingComplete(1));
        LossDetails memory lossDetails1 = LendingPoolTranche(lpd.tranches[1]).getLossDetails(1);
        assertEq(lossDetails1.lossAmount, trancheDeposits1);
        assertEq(lossDetails1.usersCount, 4);

        assertTrue(LendingPoolTranche(lpd.tranches[2]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[2]).isLossMintingComplete(1));
        LossDetails memory lossDetails2 = LendingPoolTranche(lpd.tranches[2]).getLossDetails(1);
        assertEq(lossDetails2.lossAmount, trancheDeposits2 / 2);
        assertEq(lossDetails2.usersCount, 5);
    }

    function test_batchMintLossTokens_singleCall() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount);
        uint256 trancheLossId = 1;

        // ### ACT ###
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(trancheLossId, 20);

        // ### ASSERT ###

        // assert tranche loss
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).getLossDetails(trancheLossId);
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(trancheLossId));
        assertEq(lossDetails.lossAmount, (totalUserDeposits / 2));
        assertEq(lossDetails.usersCount, usersCount);
        assertEq(lossDetails.usersMintedCount, usersCount);
        assertEq(lossDetails.totalLossShares, totalUserDeposits * 10 ** 12);

        // assert user loss tokens
        for (uint256 i; i < userAddresses.length; ++i) {
            assertEq(
                LendingPoolTranche(lpd.tranches[0]).balanceOf(userAddresses[i], trancheLossId), amounts[i] * 10 ** 12
            );
        }
    }

    function test_batchMintLossTokens_multipleCalls() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount);
        uint256 trancheLossId = 1;

        // ### ACT - mint half users ###
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(trancheLossId, 10);

        // ### ASSERT ###

        // assert tranche loss after only half users minted
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(trancheLossId));
        LossDetails memory lossDetailsPartial = LendingPoolTranche(lpd.tranches[0]).getLossDetails(trancheLossId);
        assertEq(lossDetailsPartial.usersMintedCount, 10);

        // ### ACT - mint the rest of users ###
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(trancheLossId, 12);
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).getLossDetails(trancheLossId);

        // ### ASSERT ###
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(trancheLossId));
        assertEq(lossDetails.lossAmount, (totalUserDeposits / 2));
        assertEq(lossDetails.usersCount, usersCount);
        assertEq(lossDetails.usersMintedCount, usersCount);
        assertEq(lossDetails.totalLossShares, totalUserDeposits * 10 ** 12);

        // assert user loss tokens
        for (uint256 i; i < userAddresses.length; ++i) {
            assertEq(
                LendingPoolTranche(lpd.tranches[0]).balanceOf(userAddresses[i], trancheLossId), amounts[i] * 10 ** 12
            );
        }
    }

    // function test_withdrawFirstLossCapital() public {
    //     // ### ARRANGE ###
    //     LendingPoolDeployment memory lpd = _createDefaultLendingPool();

    //     uint256 requestDepositAmount_alice = 100 * 10 ** 6;
    //     uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

    //     uint256 requestDepositAmount_bob = 250 * 10 ** 6;
    //     uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

    //     uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
    //     _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

    //     uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
    //     _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

    //     _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);
    //     _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 10 * 10 ** 6);

    //     // ### ACT ###
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             ILendingPool.WithdrawAmountCantBeGreaterThanFirstLostCapital.selector, 61 * 10 ** 6, 60 * 10 ** 6
    //         )
    //     );
    //     _withdrawFirstLossCapital(
    //         lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 61 * 10 ** 6
    //     );
    //     _withdrawFirstLossCapital(
    //         lendingPoolLoanManagerAccount, lendingPoolLoanManagerAccount, lpd.lendingPool, 20 * 10 ** 6
    //     );

    //     // ### ASSERT ###
    //     assertEq(mockUsdc.balanceOf(lendingPoolLoanManagerAccount), 20 * 10 ** 6);
    //     assertEq(mockUsdc.balanceOf(lpd.lendingPool), 330 * 10 ** 6);
    //     // assertEq(mockUsdc.balanceOf(lpd.lendingPool), ILendingPool(lpd.lendingPool).totalSupply());
    // }

    // function test_borrowLoan() public {
    //     // ### ARRANGE ###
    //     LendingPoolDeployment memory lpd = _createDefaultLendingPool();

    //     uint256 requestDepositAmount_alice = 100 * 10 ** 6;
    //     uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], requestDepositAmount_alice);

    //     uint256 requestDepositAmount_bob = 250 * 10 ** 6;
    //     uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], requestDepositAmount_bob);

    //     uint256 acceptDepositAmount_alice = 40 * 10 ** 6;
    //     _acceptDepositRequest(lpd.lendingPool, dNftId_alice, acceptDepositAmount_alice);

    //     uint256 acceptedDepositAmount_bob = 250 * 10 ** 6;
    //     _acceptDepositRequest(lpd.lendingPool, dNftId_bob, acceptedDepositAmount_bob);

    //     _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, 50 * 10 ** 6);

    //     uint256 lendingPoolTokenTotalSupplyBefore = ILendingPool(lpd.lendingPool).totalSupply();

    //     // ### ACT ###
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             ILendingPool.BorrowAmountCantBeGreaterThanAvailableAmount.selector, 341 * 10 ** 6, 340 * 10 ** 6
    //         )
    //     );
    //     _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, 341 * 10 ** 6);
    //     _borrowLoan(lendingPoolLoanManagerAccount, lpd.lendingPool, 200 * 10 ** 6);

    //     // ### ASSERT ###
    //     assertEq(mockUsdc.balanceOf(lpd.lendingPool), 140 * 10 ** 6);
    //     assertEq(mockUsdc.balanceOf(lendingPoolLoanManagerAccount), 200 * 10 ** 6);
    //     assertEq(ILendingPool(lpd.lendingPool).totalSupply(), lendingPoolTokenTotalSupplyBefore);
    // }

    function _requestAndAcceptUserDeposits(address lendingPool, uint256 userCount, address tranche, uint256 totalAmount)
        private
        returns (address[] memory userAddresses, uint256[] memory amounts)
    {
        userAddresses = new address[](userCount);
        amounts = new uint256[](userCount);

        uint256 amountLeft = totalAmount;

        for (uint256 i; i < userCount; ++i) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            userAddresses[i] = user;
            amounts[i] = totalAmount / userCount;
            amountLeft -= amounts[i];

            if (i == userCount - 1) {
                amounts[i] += amountLeft;
            }

            _allowUser(user);
            uint256 dNFT = _requestDeposit(user, lendingPool, tranche, amounts[i]);
            _acceptDepositRequest(lendingPool, dNFT, amounts[i]);
        }
    }
}
