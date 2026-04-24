// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import {LossDetails} from "../../../src/core/interfaces/lendingPool/ILendingPoolTrancheLoss.sol";
import "../../../src/core/lendingPool/LendingPoolStoppable.sol";
import "../../../src/shared/CommonErrors.sol";

interface IAcceptedRequestsExecutionTestShim {
    function CLEARING_MINT_BATCH_SIZE() external view returns (uint256);
}

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
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        _drawFunds(lpd.lendingPool, firstLossCapitalAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        // ### ASSERT ###
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        assertEq(LendingPool(lpd.lendingPool).userOwedAmount(), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), 0);
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
    }

    function test_reportLoss_singleTrancheLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 3, lpd.tranches[0], totalUserDeposits);

        _drawFunds(lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        // ### ASSERT ###

        // assert lending pool
        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        uint256 expectedBalanceLeft = firstLossCapitalAmount + totalUserDeposits - lossAmount;
        assertEq(LendingPool(lpd.lendingPool).userOwedAmount(), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[0]), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), expectedBalanceLeft);

        // assert tranche loss
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(1));
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).lossDetails(1);
        assertEq(lossDetails.lossAmount, totalUserDeposits / 2);
        assertEq(lossDetails.usersCount, 3);
    }

    function test_reportLoss_multipleTrancheLoss() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 trancheDeposits0 = 100_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 3, lpd.tranches[0], trancheDeposits0);

        uint256 trancheDeposits1 = 200_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 4, lpd.tranches[1], trancheDeposits1);

        uint256 trancheDeposits2 = 650_000 * 10 ** 6;
        _requestAndAcceptUserDeposits(lpd.lendingPool, 5, lpd.tranches[2], trancheDeposits2);

        uint256 drawAmount = firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2;
        _drawFunds(lpd.lendingPool, drawAmount);

        // ### ACT ###
        uint256 lossAmount = firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2 / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        // ### ASSERT ###
        uint256 minimumAssetAmountLeftAfterLoss =
            ILendingPoolTrancheLoss(lpd.tranches[0]).minimumAssetAmountLeftAfterLoss();

        assertEq(LendingPool(lpd.lendingPool).firstLossCapital(), 0);
        uint256 expectedBalanceLeft =
            firstLossCapitalAmount + trancheDeposits0 + trancheDeposits1 + trancheDeposits2 - lossAmount;
        assertEq(LendingPool(lpd.lendingPool).userOwedAmount(), expectedBalanceLeft);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.lendingPool), 0);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[0]), minimumAssetAmountLeftAfterLoss);
        assertEq(LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[1]), minimumAssetAmountLeftAfterLoss);
        assertEq(
            LendingPool(lpd.lendingPool).balanceOf(lpd.tranches[2]),
            trancheDeposits2 / 2 - minimumAssetAmountLeftAfterLoss * 2
        );
        assertEq(LendingPool(lpd.lendingPool).totalSupply(), expectedBalanceLeft);

        // assert tranche loss
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(1));
        LossDetails memory lossDetails0 = LendingPoolTranche(lpd.tranches[0]).lossDetails(1);
        assertEq(lossDetails0.lossAmount, trancheDeposits0 - minimumAssetAmountLeftAfterLoss);
        assertEq(lossDetails0.usersCount, 3);

        assertTrue(LendingPoolTranche(lpd.tranches[1]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[1]).isLossMintingComplete(1));
        LossDetails memory lossDetails1 = LendingPoolTranche(lpd.tranches[1]).lossDetails(1);
        assertEq(lossDetails1.lossAmount, trancheDeposits1 - minimumAssetAmountLeftAfterLoss);
        assertEq(lossDetails1.usersCount, 4);

        assertTrue(LendingPoolTranche(lpd.tranches[2]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[2]).isLossMintingComplete(1));
        LossDetails memory lossDetails2 = LendingPoolTranche(lpd.tranches[2]).lossDetails(1);
        assertEq(lossDetails2.lossAmount, trancheDeposits2 / 2 + minimumAssetAmountLeftAfterLoss * 2);
        assertEq(lossDetails2.usersCount, 5);
    }

    function test_reportLossAndBatchMintLossTokens() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 firstLossCapitalAmount = 50_000 * 10 ** 6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _drawFunds(lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;

        // ### ACT ###
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, true);
        uint256 trancheLossId = 1;

        // ### ASSERT ###

        // assert tranche loss
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).lossDetails(trancheLossId);
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
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, firstLossCapitalAmount);

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 20;
        (address[] memory userAddresses, uint256[] memory amounts) =
            _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _drawFunds(lpd.lendingPool, firstLossCapitalAmount + totalUserDeposits);

        uint256 lossAmount = firstLossCapitalAmount + totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);
        uint256 trancheLossId = 1;

        // ### ACT - mint half users ###
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(trancheLossId, 10);

        // ### ASSERT ###

        // assert tranche loss after only half users minted
        assertTrue(LendingPoolTranche(lpd.tranches[0]).isPendingLossMint());
        assertFalse(LendingPoolTranche(lpd.tranches[0]).isLossMintingComplete(trancheLossId));
        LossDetails memory lossDetailsPartial = LendingPoolTranche(lpd.tranches[0]).lossDetails(trancheLossId);
        assertEq(lossDetailsPartial.usersMintedCount, 10);

        // ### ACT - mint the rest of users ###
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(trancheLossId, 12);
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).lossDetails(trancheLossId);

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

        _drawFunds(lpd.lendingPool, totalUserDeposits);

        // ### ACT ###
        uint256 lossAmount1 = totalUserDeposits / 8;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount1, true);

        uint256 lossAmount2 = totalUserDeposits / 4;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount2, true);

        uint256 lossAmount3 = totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount3, true);

        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], 1, lossAmount1);
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], 2, lossAmount2);
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], 3, lossAmount3);

        // ### ASSERT ###
        {
            LossDetails memory lossDetails1 = LendingPoolTranche(lpd.tranches[0]).lossDetails(1);
            assertEq(lossDetails1.lossAmount, lossAmount1);
            assertEq(lossDetails1.usersCount, usersCount);
            assertEq(lossDetails1.recoveredAmount, lossAmount1);

            LossDetails memory lossDetails2 = LendingPoolTranche(lpd.tranches[0]).lossDetails(2);
            assertEq(lossDetails2.lossAmount, lossAmount2);
            assertEq(lossDetails2.usersCount, usersCount);
            assertEq(lossDetails2.recoveredAmount, lossAmount2);

            LossDetails memory lossDetails3 = LendingPoolTranche(lpd.tranches[0]).lossDetails(3);
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

        _drawFunds(lpd.lendingPool, totalUserDeposits);

        uint256 lossAmount = totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        uint256 lossId = 1;
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(lossId, usersCount);

        // ### ACT ###
        uint256 repayAmount = lossAmount / 2;
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount);

        // ### ASSERT ###
        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).lossDetails(lossId);
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

        _drawFunds(lpd.lendingPool, totalUserDeposits);

        uint256 lossAmount = totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        uint256 lossId = 1;
        LendingPoolTranche(lpd.tranches[0]).batchMintLossTokens(lossId, usersCount);
        uint256 repayAmount = lossAmount / 4;
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount);

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
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], lossId, repayAmount2);

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

    /**
     * @notice M-05 FIX: repayLoss reverts when cumulative recoveredAmount exceeds lossAmount.
     */
    function test_M05_repayLossRevertsWhenExceedingLossAmount() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 3;
        _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);

        _drawFunds(lpd.lendingPool, totalUserDeposits);

        uint256 lossAmount = totalUserDeposits / 2; // 50k loss
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, true);

        uint256 lossId = 1;

        // Repay the exact loss amount - should succeed
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, lpd.tranches[0], lossId, lossAmount);

        LossDetails memory lossDetails = LendingPoolTranche(lpd.tranches[0]).lossDetails(lossId);
        assertEq(lossDetails.recoveredAmount, lossAmount, "Recovered should equal loss");

        // Additional repayment should revert
        uint256 extraAmount = 1;
        deal(address(mockUsdc), poolFundsManagerAccount, extraAmount, true);
        vm.startPrank(poolFundsManagerAccount);
        mockUsdc.approve(address(lendingPoolManager), extraAmount);
        vm.expectRevert(abi.encodeWithSelector(ILendingPoolTrancheLoss.RecoveryExceedsLoss.selector, lossId));
        lendingPoolManager.repayLoss(lpd.lendingPool, lpd.tranches[0], lossId, extraAmount);
        vm.stopPrank();
    }

    // M-06: pending-mint accessors expose lossId and remaining user count so that step 4 self-heal
    // and backend monitoring can reason about incomplete loss-token mints.
    function test_M06_pendingLossMintAccessors() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 totalUserDeposits = 100_000 * 10 ** 6;
        uint256 usersCount = 5;
        _requestAndAcceptUserDeposits(lpd.lendingPool, usersCount, lpd.tranches[0], totalUserDeposits);
        _drawFunds(lpd.lendingPool, totalUserDeposits);

        LendingPoolTranche tranche = LendingPoolTranche(lpd.tranches[0]);

        // no pending mint initially
        assertEq(tranche.pendingLossMintId(), 0);
        assertEq(tranche.pendingLossMintUsersRemaining(), 0);

        // register loss without minting — pending state entered
        uint256 lossAmount = totalUserDeposits / 2;
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, false);

        uint256 lossId = 1;
        assertEq(tranche.pendingLossMintId(), lossId);
        assertEq(tranche.pendingLossMintUsersRemaining(), usersCount);

        // partial mint — remaining decreases
        tranche.batchMintLossTokens(lossId, 2);
        assertEq(tranche.pendingLossMintId(), lossId);
        assertEq(tranche.pendingLossMintUsersRemaining(), usersCount - 2);

        // finish mint — accessors clear
        tranche.batchMintLossTokens(lossId, usersCount - 2);
        assertEq(tranche.pendingLossMintId(), 0);
        assertEq(tranche.pendingLossMintUsersRemaining(), 0);
    }

    // M-06: CLEARING_MINT_BATCH_SIZE is exposed on the PendingPool (via AcceptedRequestsExecution).
    function test_M06_clearingMintBatchSizeExposed() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address pendingPool = LendingPool(lpd.lendingPool).pendingPool();
        assertEq(IAcceptedRequestsExecutionTestShim(pendingPool).CLEARING_MINT_BATCH_SIZE(), 100);
    }

    /**
     * @notice Proves that an FT-locked depositor can self-serve a loss recovery,
     * just like a flexible depositor. No stranded funds on FixedTermDeposit.
     *
     * Key insight: `userActiveShares` tracks *beneficial* ownership, independent of
     * where the ERC20 balance sits. When shares are moved to FixedTermDeposit for
     * custody via transferFrom, only the ERC20 balance moves — `userActiveShares[user]`
     * is untouched. The ERC20 `_update` path doesn't sync with the userActiveShares
     * mapping; that mapping is only mutated by `tranche.deposit(...)` (on mint) and
     * `removeUserActiveShares(...)` (on redeem).
     *
     * Consequence: loss tokens (ERC1155) are minted against `userActiveShares`, so
     * they land on the depositor (bob), not on the FT contract. bob can call
     * `LendingPoolManager.claimRepaidLoss(pool, tranche, lossId)` directly and
     * receive his share of any recovery, while his principal shares are still locked.
     */
    function test_ftDepositLoss_recoveryWorksForFTDepositor() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // Add an FT config on tranche[0]: 5-epoch lock, 1% per-epoch rate, open to anyone.
        vm.prank(poolManagerAccount);
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool,
            lpd.tranches[0],
            5, // epochLockDuration
            INTEREST_RATE_FULL_PERCENT / 100, // 1% per epoch
            false // whitelistedOnly
        );
        uint256 ftConfigId = 1;

        // Two depositors, equal amounts on the same tranche.
        uint256 depositAmount = 50_000 * 1e6;
        _allowUser(alice);
        _allowUser(bob);

        // Alice: flexible deposit.
        uint256 aliceDNft = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], depositAmount);
        _acceptDepositRequest(lpd.lendingPool, aliceDNft, depositAmount);

        // Bob: FT deposit. Accept auto-triggers lockFixedTermDepositAutomatically
        // via PendingPool._acceptDepositRequest, so his shares land on FixedTermDeposit.
        uint256 bobDNft =
            _requestFixedTermDeposit(bob, lpd.lendingPool, lpd.tranches[0], depositAmount, ftConfigId);
        _acceptDepositRequest(lpd.lendingPool, bobDNft, depositAmount);

        LendingPoolTranche tranche = LendingPoolTranche(lpd.tranches[0]);
        address ftContract = address(fixedTermDeposit);

        // #### Beneficial ownership (userActiveShares) vs custody (ERC20 balanceOf) ####

        // Beneficial ownership: alice and bob both have > 0, FT contract has 0.
        assertGt(tranche.userActiveShares(alice), 0, "alice userActiveShares > 0");
        assertGt(tranche.userActiveShares(bob), 0, "bob userActiveShares > 0 (beneficial ownership preserved)");
        assertEq(tranche.userActiveShares(ftContract), 0, "FT contract userActiveShares == 0");
        assertEq(
            tranche.userActiveShares(alice),
            tranche.userActiveShares(bob),
            "alice and bob are equal beneficial owners"
        );

        // ERC20 custody: alice holds her balance, bob's moved to FT contract.
        assertGt(tranche.balanceOf(alice), 0, "alice ERC20 balance > 0");
        assertEq(tranche.balanceOf(bob), 0, "bob ERC20 balance == 0 (custody moved to FT)");
        assertGt(tranche.balanceOf(ftContract), 0, "FT contract holds ERC20 for bob");

        _drawFunds(lpd.lendingPool, depositAmount * 2);

        // ### ACT: loss lands on the tranche ###
        uint256 lossAmount = depositAmount; // 50% haircut on tranche assets
        _reportLoss(poolFundsManagerAccount, lpd.lendingPool, lossAmount, true);
        uint256 lossId = 1;

        // #### ERC1155 loss tokens go to beneficial owners, NOT the FT custodian ####
        assertGt(tranche.balanceOf(alice, lossId), 0, "alice holds loss tokens");
        assertGt(tranche.balanceOf(bob, lossId), 0, "bob holds loss tokens (despite FT custody)");
        assertEq(
            tranche.balanceOf(ftContract, lossId),
            0,
            "FT contract holds ZERO loss tokens - not a beneficial holder, no forwarding needed"
        );
        assertEq(
            tranche.balanceOf(alice, lossId),
            tranche.balanceOf(bob, lossId),
            "equal deposits -> equal loss tokens"
        );

        // Share-price haircut applied uniformly.
        assertLt(
            tranche.convertToAssets(tranche.userActiveShares(bob)),
            depositAmount,
            "bob's position value dropped via share-price haircut"
        );

        // ### ACT: borrower recovers the full loss ###
        _repayLoss(poolFundsManagerAccount, lpd.lendingPool, address(tranche), lossId, lossAmount);

        // #### Both depositors self-serve claim — no special path for FT ####
        uint256 aliceUsdcBefore = mockUsdc.balanceOf(alice);
        uint256 aliceClaimed = _claimRepaidLoss(alice, lpd.lendingPool, address(tranche), lossId);
        assertGt(aliceClaimed, 0, "alice claims recovery directly");
        assertEq(mockUsdc.balanceOf(alice) - aliceUsdcBefore, aliceClaimed, "alice received USDC");

        uint256 bobUsdcBefore = mockUsdc.balanceOf(bob);
        uint256 bobClaimed = _claimRepaidLoss(bob, lpd.lendingPool, address(tranche), lossId);
        assertGt(bobClaimed, 0, "bob claims recovery directly - no FT intervention needed");
        assertEq(mockUsdc.balanceOf(bob) - bobUsdcBefore, bobClaimed, "bob received USDC");

        // Equal pro-rata within rounding.
        assertApproxEqAbs(aliceClaimed, bobClaimed, 1, "equal recovery for equal positions");

        // Nothing stranded: FT contract's loss-token balance unchanged (still 0),
        // and the tranche's USDC is fully distributed (modulo rounding dust).
        assertEq(tranche.balanceOf(ftContract, lossId), 0, "FT contract never held tokens; nothing to sweep");
        assertApproxEqAbs(mockUsdc.balanceOf(address(tranche)), 0, 2, "all recovery USDC claimed");
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
