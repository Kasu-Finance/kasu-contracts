// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract PerformanceFeeTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_performanceFeeIsCollectedOnlyIfUserStakesAndLends() public {
        // EPOCH 0

        // users lock
        _lock(alice, 100 * 1e18, lockPeriod30);
        _lock(carol, 100 * 1e18, lockPeriod30);
        _lock(user5, 100 * 1e18, lockPeriod30);

        skip(35 days);

        // EPOCH 5

        // Deploy 2 pools
        uint256 interestRate_0_1_percent = INTEREST_RATE_FULL_PERCENT / 1000;
        CreateTrancheConfig[] memory tranches = new CreateTrancheConfig[](3);
        tranches[0] = CreateTrancheConfig(30_00, interestRate_0_1_percent, 0, type(uint256).max);
        tranches[1] = CreateTrancheConfig(20_00, interestRate_0_1_percent, 0, type(uint256).max);
        tranches[2] = CreateTrancheConfig(50_00, interestRate_0_1_percent, 0, type(uint256).max);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig({
            poolName: "Pool1",
            poolSymbol: "P1",
            targetExcessLiquidityPercentage: 0,
            minExcessLiquidityPercentage: 0,
            tranches: tranches,
            poolAdmin: lendingPoolAdminAccount,
            drawRecipient: poolFundsManagerAccount,
            desiredDrawAmount: 0
        });
        LendingPoolDeployment memory lpd1 = _createLendingPoolFromConfig(createPoolConfig);

        createPoolConfig.poolName = "Pool2";
        createPoolConfig.poolSymbol = "P2";
        tranches = new CreateTrancheConfig[](1);
        tranches[0] = CreateTrancheConfig(100_00, interestRate_0_1_percent, 0, type(uint256).max);
        createPoolConfig.tranches = tranches;
        LendingPoolDeployment memory lpd2 = _createLendingPoolFromConfig(createPoolConfig);

        _depositFirstLossCapital(poolFundsManagerAccount, lpd1.lendingPool, 1_000 * 1e6);
        _depositFirstLossCapital(poolFundsManagerAccount, lpd2.lendingPool, 1_000 * 1e6);

        // Alice deposits to both pools all tranches
        _requestDeposit(alice, lpd1.lendingPool, lpd1.tranches[0], 1_000 * 1e6);
        _requestDeposit(alice, lpd1.lendingPool, lpd1.tranches[1], 1_000 * 1e6);
        _requestDeposit(alice, lpd1.lendingPool, lpd1.tranches[2], 1_000 * 1e6);
        _requestDeposit(alice, lpd2.lendingPool, lpd2.tranches[0], 1_000 * 1e6);

        // Bob deposits to both pools all tranches
        _requestDeposit(bob, lpd1.lendingPool, lpd1.tranches[0], 1_000 * 1e6);
        _requestDeposit(bob, lpd1.lendingPool, lpd1.tranches[1], 1_000 * 1e6);
        _requestDeposit(bob, lpd1.lendingPool, lpd1.tranches[2], 1_000 * 1e6);
        _requestDeposit(bob, lpd2.lendingPool, lpd2.tranches[0], 1_000 * 1e6);

        // Carol deposits to pool 1 tranche 2
        _requestDeposit(carol, lpd2.lendingPool, lpd2.tranches[0], 1_000 * 1e6);

        // David deposits to pool 2 tranche 0
        _requestDeposit(david, lpd1.lendingPool, lpd1.tranches[0], 1_000 * 1e6);

        skip(6 days);

        // CLEARING 5
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        uint256 currentEpoch = systemVariables.currentEpochNumber();

        uint256[] memory trancheDesiredRatios1 = new uint256[](3);
        trancheDesiredRatios1[0] = 20_00;
        trancheDesiredRatios1[1] = 30_00;
        trancheDesiredRatios1[2] = 50_00;

        // clearing pool 1 (accept all deposits)
        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(6_900 * 1e6, trancheDesiredRatios1, 10_00, 0);
        _doClearing(poolClearingManagerAccount, lpd1.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration1, true);

        // clearing pool 2 (accept all deposits)
        uint256[] memory trancheDesiredRatios2 = new uint256[](1);
        trancheDesiredRatios2[0] = 100_00;
        ClearingConfiguration memory clearingConfiguration2 =
            ClearingConfiguration(2_900 * 1e6, trancheDesiredRatios2, 10_00, 0);
        _doClearing(poolClearingManagerAccount, lpd2.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration2, true);

        skip(1 days);

        // EPOCH 6

        _lock(bob, 100 * 1e18, lockPeriod30);

        _requestDeposit(user5, lpd1.lendingPool, lpd1.tranches[2], 1_000 * 1e6);

        // Alice withdraws from pool 2
        _requestWithdrawal(alice, lpd2.lendingPool, lpd2.tranches[0], ILendingPoolTranche(lpd2.tranches[0]).balanceOf(alice));
        // Carol partially withdraws from pool 2 tranche 2
        _requestWithdrawal(carol, lpd2.lendingPool, lpd2.tranches[0], ILendingPoolTranche(lpd2.tranches[0]).balanceOf(carol) / 2);

        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd2.lendingPool, 1_600 * 1e6);

        skip(6 days);

        // CLEARING 6
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        currentEpoch = systemVariables.currentEpochNumber();

        uint256 totalRewards2 = (ILendingPool(lpd2.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;
        uint256 totalRewards1 = (ILendingPool(lpd1.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;

        // clearing pool 2 (accept all withdrawals)
        clearingConfiguration2.drawAmount = 0;
        _doClearing(poolClearingManagerAccount, lpd2.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration2, true);

        // 5% of yield is distributed to users as collected fees
        assertApproxEqAbs(_KSULocking.rewards(alice), totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(bob), totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(carol), totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(david), 0, 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), 0, 0);

        uint256[5] memory userRewardsBefore = _getUserRewards();

        // clearing pool 1 (accept all deposits)
        clearingConfiguration1.drawAmount = 1_000 * 1e6;
        _doClearing(poolClearingManagerAccount, lpd1.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration1, true);

        assertApproxEqAbs(_KSULocking.rewards(alice), userRewardsBefore[0] + totalRewards1 / 4, 1);
        assertApproxEqAbs(_KSULocking.rewards(bob), userRewardsBefore[1] + totalRewards1 / 4, 1);
        assertApproxEqAbs(_KSULocking.rewards(carol), userRewardsBefore[2] + totalRewards1 / 4, 1);
        assertApproxEqAbs(_KSULocking.rewards(david), userRewardsBefore[3], 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), userRewardsBefore[4] + totalRewards1 / 4, 0);

        skip(1 days);

        // EPOCH 7

        // User5 unlocks all deposits
        _unlockAll(user5, 0);

        // Bob withdraws from all pools
        _requestWithdrawal(bob, lpd1.lendingPool, lpd1.tranches[0], ILendingPoolTranche(lpd1.tranches[0]).balanceOf(bob));
        _requestWithdrawal(bob, lpd1.lendingPool, lpd1.tranches[1], ILendingPoolTranche(lpd1.tranches[1]).balanceOf(bob));
        _requestWithdrawal(bob, lpd1.lendingPool, lpd1.tranches[2], ILendingPoolTranche(lpd1.tranches[2]).balanceOf(bob));
        _requestWithdrawal(bob, lpd2.lendingPool, lpd2.tranches[0], ILendingPoolTranche(lpd2.tranches[0]).balanceOf(bob));

        // repay owed funds for pool 1
        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd1.lendingPool, 3_100 * 1e6);

        // repaying owed funds for pool 2
        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd2.lendingPool, 1_100 * 1e6);

        skip(6 days);

        // CLEARING 7
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        currentEpoch = systemVariables.currentEpochNumber();

        totalRewards2 = (ILendingPool(lpd2.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;
        totalRewards1 = (ILendingPool(lpd1.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;
        userRewardsBefore = _getUserRewards();

        // clearing pool 2 (accept all withdrawals)
        clearingConfiguration2.drawAmount = 0;
        _doClearing(poolClearingManagerAccount, lpd2.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration2, true);

        assertApproxEqAbs(_KSULocking.rewards(alice), userRewardsBefore[0] + totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(bob), userRewardsBefore[1] + totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(carol), userRewardsBefore[2] + totalRewards2 / 3, 1);
        assertApproxEqAbs(_KSULocking.rewards(david), userRewardsBefore[3], 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), userRewardsBefore[4], 0);

        userRewardsBefore = _getUserRewards();

        // clearing pool 1 (accept all withdrawals)
        clearingConfiguration1.drawAmount = 0;
        _doClearing(poolClearingManagerAccount, lpd1.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration1, true);

        assertApproxEqAbs(_KSULocking.rewards(alice), userRewardsBefore[0] + totalRewards1 / 2, 1);
        assertApproxEqAbs(_KSULocking.rewards(bob), userRewardsBefore[1], 1);
        assertApproxEqAbs(_KSULocking.rewards(carol), userRewardsBefore[2] + totalRewards1 / 2, 1);
        assertApproxEqAbs(_KSULocking.rewards(david), userRewardsBefore[3], 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), userRewardsBefore[4], 0);

        skip(1 days);

        // EPOCH 8

        // Everyone withdraws from all pools
        _requestWithdrawal(alice, lpd1.lendingPool, lpd1.tranches[0], ILendingPoolTranche(lpd1.tranches[0]).balanceOf(alice));
        _requestWithdrawal(alice, lpd1.lendingPool, lpd1.tranches[1], ILendingPoolTranche(lpd1.tranches[1]).balanceOf(alice));
        _requestWithdrawal(alice, lpd1.lendingPool, lpd1.tranches[2], ILendingPoolTranche(lpd1.tranches[2]).balanceOf(alice));

        _requestWithdrawal(carol, lpd2.lendingPool, lpd2.tranches[0], ILendingPoolTranche(lpd2.tranches[0]).balanceOf(carol));

        _requestWithdrawal(user5, lpd1.lendingPool, lpd1.tranches[2], ILendingPoolTranche(lpd1.tranches[2]).balanceOf(user5));

        // repay owed funds for pool 1
        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd1.lendingPool, ILendingPool(lpd1.lendingPool).userOwedAmount());

        // repaying owed funds for pool 2
        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd2.lendingPool, ILendingPool(lpd2.lendingPool).userOwedAmount());

        skip(6 days);

        // CLEARING 8
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        currentEpoch = systemVariables.currentEpochNumber();

        totalRewards2 = (ILendingPool(lpd2.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;
        totalRewards1 = (ILendingPool(lpd1.lendingPool).totalSupply() - 1_000 * 1e6) * interestRate_0_1_percent * 5_00 / INTEREST_RATE_FULL_PERCENT / FULL_PERCENT;
        userRewardsBefore = _getUserRewards();

        // clearing pool 2 (accept all withdrawals)
        clearingConfiguration2.drawAmount = 0;
        _doClearing(poolClearingManagerAccount, lpd2.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration2, true);

        assertApproxEqAbs(_KSULocking.rewards(alice), userRewardsBefore[0] + totalRewards2, 1);
        assertApproxEqAbs(_KSULocking.rewards(bob), userRewardsBefore[1], 1);
        assertApproxEqAbs(_KSULocking.rewards(carol), userRewardsBefore[2], 1);
        assertApproxEqAbs(_KSULocking.rewards(david), userRewardsBefore[3], 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), userRewardsBefore[4], 0);
    
        userRewardsBefore = _getUserRewards();

        // clearing pool 1 (accept all withdrawals)
        clearingConfiguration1.drawAmount = 0;
        _doClearing(poolClearingManagerAccount, lpd1.lendingPool, currentEpoch, type(uint256).max, type(uint256).max, clearingConfiguration1, true);

        assertApproxEqAbs(_KSULocking.rewards(alice), userRewardsBefore[0], 0);
        assertApproxEqAbs(_KSULocking.rewards(bob), userRewardsBefore[1], 0);
        assertApproxEqAbs(_KSULocking.rewards(carol), userRewardsBefore[2], 0);
        assertApproxEqAbs(_KSULocking.rewards(david), userRewardsBefore[3], 0);
        assertApproxEqAbs(_KSULocking.rewards(user5), userRewardsBefore[4], 0);
    }

    function _getUserRewards() private view returns (uint256[5] memory) {
        return [
            _KSULocking.rewards(alice),
            _KSULocking.rewards(bob),
            _KSULocking.rewards(carol),
            _KSULocking.rewards(david),
            _KSULocking.rewards(user5)
        ];
    }
}
