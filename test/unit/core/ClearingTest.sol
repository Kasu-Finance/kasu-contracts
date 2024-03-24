// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract ClearingTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_calculatePendingRequestsPriority() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // tranche 1
        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 1e6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 250 * 1e6);
        uint256 dNftId_carol = _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 50 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 10 * 1e6);
        _requestDeposit(user5, lpd.lendingPool, lpd.tranches[0], 500 * 1e6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 1e6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 200 * 1e6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_carol, 50 * 1e6);

        _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[0], 200 * 10 ** 18);

        // tranche 2
        _requestDeposit(user6, lpd.lendingPool, lpd.tranches[1], 150 * 1e6);
        _requestDeposit(user7, lpd.lendingPool, lpd.tranches[1], 60 * 1e6);

        // tranche 3
        uint256 dNftId_user8 = _requestDeposit(user8, lpd.lendingPool, lpd.tranches[2], 80 * 1e6);
        _requestDeposit(user9, lpd.lendingPool, lpd.tranches[2], 20 * 1e6);
        _requestDeposit(user10, lpd.lendingPool, lpd.tranches[2], 180 * 1e6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_user8, 40 * 1e6);

        _requestWithdrawal(user8, lpd.lendingPool, lpd.tranches[2], 20 * 10 ** 18);

        ForceWithdrawalInput[] memory input1 = new ForceWithdrawalInput[](1);
        input1[0] = ForceWithdrawalInput(lpd.tranches[2], user8, 10 * 10 ** 18);
        _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input1)[0];

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        // user locking
        // loyalty levels: 0-1%: 0, 1%-3%:1, 3%+: 2
        _lock(bob, 3 ether, lockPeriod180); // 0,25 * 3e18 * 2e18 / 1e18 / 1e12 = 1.5 usdc / 250 usdc -> 0.6% -> 0
        _lock(user5, 8 ether, lockPeriod360); // 0,5 * 8e18 * 2e18 / 1e18 / 1e12 = 8 usdc / 500 usdc- > 1.6% -> 1
        _lock(alice, 25 ether, lockPeriod30); // 0,05 * 15e18 * 2e18 / 1e18 / 1e12 = 2.5 usdc / 100 usdc = 2.5% -> 1
        _lock(carol, 5 ether, lockPeriod360); // 0,5 * 5e18 * 2e18 / 1e18 / 1e12 = 5 usdc / 50 usdc- > 10% -> 2
        _lock(david, 5 ether, lockPeriod360); // 0,5 * 5e18 * 2e18 / 1e18 / 1e12 = 5 usdc / 50 usdc- > 50% -> 2

        skip(6 days);

        userManager.batchCalculateUserLoyaltyLevels(20);

        // ### ACT ###
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 20, 10);

        // ### ASSERT ###
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        PendingDeposits memory pendingDeposits = pendingPool.getPendingDeposits(currentEpoch);
        assertEq(pendingDeposits.totalDepositAmount, 1070 * 1e6);

        assertEq(pendingDeposits.trancheDepositsAmounts.length, 3);
        assertEq(pendingDeposits.trancheDepositsAmounts[0], 620 * 1e6);
        assertEq(pendingDeposits.trancheDepositsAmounts[1], 210 * 1e6);
        assertEq(pendingDeposits.trancheDepositsAmounts[2], 240 * 1e6);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][0], 50 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][1], 560 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][2], 10 * 1e6);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][0], 210 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][1], 0);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][2], 0);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][0], 240 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][1], 0);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][2], 0);

        PendingWithdrawals memory pendingWithdrawals = pendingPool.getPendingWithdrawals(currentEpoch);
        assertEq(pendingWithdrawals.totalWithdrawalsAmount, 270 * 1e6);

        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[0], 220 * 1e6);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[1], 40 * 1e6);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[2], 0);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[3], 10 * 1e6);
    }

    function test_executeAcceptedRequestsBatch() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // J0: 20K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 6_000 * 1e6);
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 5_000 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 5_000 * 1e6);
        // J1: 0
        // J2: 30K
        _requestDeposit(user16, lpd.lendingPool, lpd.tranches[0], 8_000 * 1e6);
        _requestDeposit(user17, lpd.lendingPool, lpd.tranches[0], 7_000 * 1e6);
        _requestDeposit(user18, lpd.lendingPool, lpd.tranches[0], 12_000 * 1e6);
        _requestDeposit(user19, lpd.lendingPool, lpd.tranches[0], 3_000 * 1e6);
        // M0: 10K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[1], 2_000 * 1e6);
        _requestDeposit(user5, lpd.lendingPool, lpd.tranches[1], 2_000 * 1e6);
        _requestDeposit(user6, lpd.lendingPool, lpd.tranches[1], 6_000 * 1e6);
        // M1: 25K
        _requestDeposit(user9, lpd.lendingPool, lpd.tranches[1], 6_000 * 1e6);
        _requestDeposit(user10, lpd.lendingPool, lpd.tranches[1], 2_000 * 1e6);
        _requestDeposit(user11, lpd.lendingPool, lpd.tranches[1], 8_000 * 1e6);
        _requestDeposit(user12, lpd.lendingPool, lpd.tranches[1], 9_000 * 1e6);
        // M2: 5K
        _requestDeposit(user16, lpd.lendingPool, lpd.tranches[1], 2_000 * 1e6);
        _requestDeposit(user19, lpd.lendingPool, lpd.tranches[1], 3_000 * 1e6);
        // S0: 10K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[2], 1_000 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[2], 1_000 * 1e6);
        _requestDeposit(user7, lpd.lendingPool, lpd.tranches[2], 5_000 * 1e6);
        _requestDeposit(user8, lpd.lendingPool, lpd.tranches[2], 3_000 * 1e6);
        // S1: 0
        // S2: 25K
        _requestDeposit(user17, lpd.lendingPool, lpd.tranches[2], 6_000 * 1e6);
        _requestDeposit(user18, lpd.lendingPool, lpd.tranches[2], 4_000 * 1e6);
        _requestDeposit(user19, lpd.lendingPool, lpd.tranches[2], 10_000 * 1e6);
        _requestDeposit(user20, lpd.lendingPool, lpd.tranches[2], 5_000 * 1e6);

        // loyalty levels: 0-1%: 0, 1%-3%:1, 3%+: 2
        // P0: alice: 7k, bob: 6k, carol: 5K, david: 6K, user5: 4K, user6: 6K, user7: 5K, user8:3K
        _lock(alice, 100 * 1e18, lockPeriod30);
        _lock(bob, 100 * 1e18, lockPeriod30);
        _lock(carol, 100 * 1e18, lockPeriod30);
        _lock(david, 100 * 1e18, lockPeriod30);
        _lock(user5, 100 * 1e18, lockPeriod30);
        _lock(user6, 100 * 1e18, lockPeriod30);
        // user7 no lock amount
        // user8 no lock amount
        // P1: user9: 6K, user10: 2K, user11: 8K, user12: 9K, user13, user14, user15
        _lock(user9, 50 * 1e18, lockPeriod720);
        _lock(user10, 20 * 1e18, lockPeriod720);
        _lock(user11, 50 * 1e18, lockPeriod720);
        _lock(user12, 50 * 1e18, lockPeriod720);
        // P2: user16: 10K, user17: 15K, user18: 19K, user19: 16K, user20: 5K
        _lock(user16, 5_000 * 1e18, lockPeriod720);
        _lock(user17, 25_000 * 1e18, lockPeriod720);
        _lock(user18, 30_000 * 1e18, lockPeriod720);
        _lock(user19, 25_000 * 1e18, lockPeriod720);
        _lock(user20, 8_000 * 1e18, lockPeriod720);

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);
        userManager.batchCalculateUserLoyaltyLevels(10);
        userManager.batchCalculateUserLoyaltyLevels(10);

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        // ### ACT ###

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;
        ClearingConfiguration memory clearingConfiguration =
            ClearingConfiguration(100_000 * 1e6, trancheDesiredRatios, 0, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch, clearingConfiguration);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch, 10, 10);

        // ### ASSERT ###

        // assert balance tranche
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[0]), 20_000 * 1e6, 1);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[1]), 20_000 * 1e6, 1);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[2]), 25_000 * 1e6, 1);
    }
}
