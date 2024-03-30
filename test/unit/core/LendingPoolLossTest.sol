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
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_reportLoss_firstLossCapitalLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);

        // ### ASSERT ###
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        assertEq(LendingPool(lpd.lendingPool).borrowedAmount(), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), 0);
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
    }

    function test_reportLoss_singleTrancheLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 3, lpd.tranches[0], totalUserDeposits);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);

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

    function test_reportLoss_multipleTrancheLoss() public {
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
        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, borrowAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2 / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);

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

    function test_reportLossAndBatchMintLossTokens() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;

        // ### ACT ###
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, true);
        uint256 trancheLossId = 1;

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

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);
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

    function test_reportLoss_multipleTimes() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 19;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, totalUserDeposits);

        // ### ACT ###
        uint256 lossAmount1 = totalUserDeposits / 8;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount1, true);

        uint256 lossAmount2 = totalUserDeposits / 4;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount2, true);

        uint256 lossAmount3 = totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount3, true);

        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], 1, lossAmount1);
        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], 2, lossAmount2);
        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], 3, lossAmount3);

        // ### ASSERT ###
        {
            LossDetails memory lossDetails1 = LendingPoolTranche(lpd.tranches[0]).getLossDetails(1);
            assertEq(lossDetails1.lossAmount, lossAmount1);
            assertEq(lossDetails1.usersCount, usersCount);
            assertEq(lossDetails1.recoveredAmount, lossAmount1);

            LossDetails memory lossDetails2 = LendingPoolTranche(lpd.tranches[0]).getLossDetails(2);
            assertEq(lossDetails2.lossAmount, lossAmount2);
            assertEq(lossDetails2.usersCount, usersCount);
            assertEq(lossDetails2.recoveredAmount, lossAmount2);

            LossDetails memory lossDetails3 = LendingPoolTranche(lpd.tranches[0]).getLossDetails(3);
            assertEq(lossDetails3.lossAmount, lossAmount3);
            assertEq(lossDetails3.usersCount, usersCount);
            assertEq(lossDetails3.recoveredAmount, lossAmount3);
        }

        for (uint256 i; i < userAddresses.length; ++i) {
            assertEq(LendingPoolTranche(lpd.tranches[0]).balanceOf(userAddresses[i], 1), amounts[i] * 10 ** 12);
            assertEq(LendingPoolTranche(lpd.tranches[0]).balanceOf(userAddresses[i], 2), amounts[i] * 10 ** 12);
            assertEq(LendingPoolTranche(lpd.tranches[0]).balanceOf(userAddresses[i], 3), amounts[i] * 10 ** 12);
        }

        for (uint256 i; i < 1; ++i) {
            uint256 claimedAmount1 = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], 1);
            uint256 claimedAmount2 = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], 2);
            uint256 claimedAmount3 = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], 3);

            assertApproxEqAbs(claimedAmount1, lossAmount1 * amounts[i] / totalUserDeposits, 1);
            assertApproxEqAbs(claimedAmount2, lossAmount2 * amounts[i] / totalUserDeposits, 1);
            assertApproxEqAbs(claimedAmount3, lossAmount3 * amounts[i] / totalUserDeposits, 1);
        }
    }

    function test_repayLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, totalUserDeposits);

        uint256 lossAmount = totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);

        uint256 lossId = 1;
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(lossId, usersCount);

        // ### ACT ###
        uint256 repayAmount = lossAmount / 2;
        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount);

        // ### ASSERT ###
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).getLossDetails(lossId);
        assertEq(lossDetails.recoveredAmount, repayAmount);
        assertEq(mockUsdc.balanceOf(lpd.tranches[0]), repayAmount);
    }

    function test_claimRepaidLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _borrowLoanImmediate(lendingPoolLoanManagerAccount, lpd.lendingPool, totalUserDeposits);

        uint256 lossAmount = totalUserDeposits / 2;
        _reportLoss(lendingPoolLoanManagerAccount, lpd.lendingPool, lossAmount, false);

        uint256 lossId = 1;
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(lossId, usersCount);
        uint256 repayAmount = lossAmount / 4;
        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount);

        // ### ACT / ASSERT ###
        // claim first half of users
        for (uint256 i; i < userAddresses.length / 2; ++i) {
            uint256 balanceBefore = mockUsdc.balanceOf(userAddresses[i]);

            uint256 claimedAmount = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], lossId);

            uint256 expectedClaimedAmount = amounts[i] / 2 / 4;
            assertApproxEqAbs(claimedAmount, expectedClaimedAmount, 1);

            uint256 balanceAfter = mockUsdc.balanceOf(userAddresses[i]);
            assertApproxEqAbs(balanceAfter - balanceBefore, expectedClaimedAmount, 1);
        }

        // ### ARRANGE - repay loss again ###
        uint256 repayAmount2 = lossAmount / 2;
        _repayLoss(lendingPoolBorrowerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount2);

        // ### ACT / ASSERT ###
        // claim first half of users
        for (uint256 i; i < userAddresses.length / 2; ++i) {
            uint256 balanceBefore = mockUsdc.balanceOf(userAddresses[i]);

            uint256 claimedAmount = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], lossId);

            uint256 expectedClaimedAmount = amounts[i] / 2 / 2;
            assertApproxEqAbs(claimedAmount, expectedClaimedAmount, 1);

            uint256 balanceAfter = mockUsdc.balanceOf(userAddresses[i]);
            assertApproxEqAbs(balanceAfter - balanceBefore, expectedClaimedAmount, 1);
        }

        // claim for users that haven't claimed before
        for (uint256 i = userAddresses.length / 2; i < userAddresses.length; ++i) {
            uint256 balanceBefore = mockUsdc.balanceOf(userAddresses[i]);

            uint256 claimedAmount = _claimRepaidLoss(userAddresses[i], lpd.lendingPool, lpd.tranches[0], lossId);

            uint256 expectedClaimedAmount = amounts[i] / 2 / 2 + amounts[i] / 2 / 4;
            assertApproxEqAbs(claimedAmount, expectedClaimedAmount, 1);

            uint256 balanceAfter = mockUsdc.balanceOf(userAddresses[i]);
            assertApproxEqAbs(balanceAfter - balanceBefore, expectedClaimedAmount, 1);
        }

        assertApproxEqAbs(mockUsdc.balanceOf(lpd.tranches[0]), 0, usersCount);
    }

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
            amounts[i] = amountLeft / userCount;
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
