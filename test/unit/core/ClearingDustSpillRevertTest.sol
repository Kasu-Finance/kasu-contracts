// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

/// @notice Regression test for the Step-4 deposit-execution double-burn DoS.
///
/// Bug: in `AcceptedRequestsExecution._executeAcceptedRequestsBatch` the per-user
/// tranche split loop computes each tranche's accepted amount from the *original*
/// request size and rounds up on a remainder. For the smallest depositor in a
/// priority group whose deposits spill from a lower tranche into a higher one, the
/// round-up consumes the whole request in the lower tranche, which drives the dNFT's
/// stored `assetAmount` to 0 and burns it. The loop then continues to the spill
/// tranche (whose group-accepted amount is still > 0), recomputes a 0 user amount and
/// calls `_acceptDepositRequest(burnedNft, ..., 0)`. The `nftExists` modifier reverts
/// with `ERC721NonexistentToken`, which bubbles up and reverts `doClearing()` — the
/// pool can no longer advance past the epoch.
///
/// This test arranges exactly that spill: a junior-tranche priority group containing a
/// 1-unit "dust" depositor, with desired ratios that force the junior group to spill
/// into the higher tranches. Before the fix, `doClearing()` reverts. After the fix it
/// must clear cleanly.
contract ClearingDustSpillRevertTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    /// Creates a 3-tranche pool with a 1-unit minimum deposit so a dust deposit is allowed.
    function _createDustPool() internal returns (LendingPoolDeployment memory lpd) {
        uint256 minDepositAmount = 1; // allow 1-unit dust deposits
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 600_000 * 1e6;

        CreateTrancheConfig[] memory tranches = new CreateTrancheConfig[](3);
        // ratio, interestRate, minDeposit, maxDeposit
        tranches[0] = CreateTrancheConfig(10_00, 0, minDepositAmount, maxDepositAmount);
        tranches[1] = CreateTrancheConfig(20_00, 0, minDepositAmount, maxDepositAmount);
        tranches[2] = CreateTrancheConfig(70_00, 0, minDepositAmount, maxDepositAmount);

        CreatePoolConfig memory cfg = CreatePoolConfig(
            "Dust Pool",
            "DUST",
            targetExcessLiquidityPercentage,
            minExcessLiquidityPercentage,
            tranches,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );
        return _createLendingPoolFromConfig(cfg);
    }

    function test_clearing_dustDepositorInSpillingGroup_doesNotBrickClearing() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDustPool();

        // interest rates to 0% so amounts stay exact across tranches
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);
        vm.startPrank(poolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[2], 0);
        vm.stopPrank();

        // All deposits go into the JUNIOR tranche (index 0), single priority group
        // (no locking => everyone is loyalty level 0). The junior tranche desired ratio
        // is only 10%, so the bulk of the junior priority group spills up into the
        // mezzo/senior tranches during clearing.
        //
        // The dust depositor (1 unit) is the trigger: its junior split floors to 0,
        // rounds up to 1 (== full request) and burns the dNFT, after which the spill
        // tranche re-touches the burned token with a 0 amount.
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 100_000 * 1e6);
        uint256 dustNft = _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 1); // 1 unit dust

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);

        uint256 currentEpoch = systemVariables.currentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 10_00; // junior only absorbs 10% -> rest spills up
        trancheDesiredRatios[1] = 20_00;
        trancheDesiredRatios[2] = 70_00;

        // large draw + max excess so the full deposit amount is accepted and must be
        // distributed (and therefore spilled) across the tranches.
        ClearingConfiguration memory clearingConfig =
            ClearingConfiguration(200_000 * 1e6, trancheDesiredRatios, 100_00, 0);

        // ### ACT ###
        // Before the fix this reverts with ERC721NonexistentToken and bricks the epoch.
        _doClearing(
            poolClearingManagerAccount, lpd.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfig, true
        );

        // ### ASSERT ###
        // Clearing completed: the dust dNFT was consumed (burned via accept) and the
        // epoch advanced. All requests were processed without reverting.
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        assertEq(pendingPool.totalSupply(), 0, "all deposit requests should be processed");
        assertEq(pendingPool.balanceOf(carol), 0, "dust dNFT must be consumed");
        dustNft; // silence unused warning if compiler optimizes
    }
}
