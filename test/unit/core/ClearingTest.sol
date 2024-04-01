// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract ClearingTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_calculatePendingRequestsPriority() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // set interest rates to 0%
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);

        vm.startPrank(lendingPoolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[2], 0);
        vm.stopPrank();

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

        // set interest rates to 0%
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);

        vm.startPrank(lendingPoolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], 0);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[2], 0);
        vm.stopPrank();

        // deposit requests: total 100K
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
        // S2: 35K
        _requestDeposit(user17, lpd.lendingPool, lpd.tranches[2], 6_000 * 1e6);
        _requestDeposit(user18, lpd.lendingPool, lpd.tranches[2], 4_000 * 1e6);
        _requestDeposit(user19, lpd.lendingPool, lpd.tranches[2], 10_000 * 1e6);
        _requestDeposit(user20, lpd.lendingPool, lpd.tranches[2], 15_000 * 1e6);

        // loyalty levels config: 0-1%: 0, 1%-3%:1, 3%+: 2
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

        uint256 currentEpoch1 = systemVariables.getCurrentEpochNumber();

        // ### ACT ###

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;

        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(100_000 * 1e6, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch1, clearingConfiguration1);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);

        // ### ASSERT ###

        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 10_000 * 1e6, 2);

        // ## Assert tranche balance ##
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[0]), 20_000 * 1e6, 1);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[1]), 30_000 * 1e6, 1);
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[2]), 60_000 * 1e6, 1);

        // ## Assert user balance per tranche ##
        // algo: J2J1J0 M2J2M1J1M0J0 S2M2J2S1M1J1S0M0J0
        ILendingPoolTranche junior = ILendingPoolTranche(lpd.tranches[0]);
        ILendingPoolTranche mezzo = ILendingPoolTranche(lpd.tranches[1]);
        ILendingPoolTranche senior = ILendingPoolTranche(lpd.tranches[2]);

        // # P2 #
        // J2 30K -> J 20K
        assertApproxEqAbs(junior.convertToAssets(junior.balanceOf(user16)), 5333_333_333, 1);
        assertApproxEqAbs(junior.convertToAssets(junior.balanceOf(user17)), 4666_666_666, 1);
        assertApproxEqAbs(junior.convertToAssets(junior.balanceOf(user18)), 8000_000_000, 1);
        assertApproxEqAbs(junior.convertToAssets(junior.balanceOf(user19)), 2000_000_000, 1);
        // M2 5K -> M 5K,  J2 30K -> M 10K
        // 2000 + 2666
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user16)), 4666_666_666, 1);
        // 3000 + 1000
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user19)), 4000_000_000, 1);
        // S2 35K -> S 35K
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user17)), 6000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user18)), 4000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user19)), 10000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user20)), 15000_000_000, 1);

        // # P1 #
        // M1 25K -> M 15K
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user9)), 3600_000_000, 1);
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user10)), 1200_000_000, 1);
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user11)), 4800_000_000, 1);
        assertApproxEqAbs(mezzo.convertToAssets(mezzo.balanceOf(user12)), 5400_000_000, 1);
        // M1 25K -> S 10K
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user9)), 2400_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user10)), 800_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user11)), 3200_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user12)), 3600_000_000, 1);

        // # P0 #
        // S0 10K -> S 10K
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(david)), 1000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user7)), 5000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user8)), 3000_000_000, 1);
        // S0 10K -> S 10K + M0 10K -> S 5K
        // 1000 + 1000
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(alice)), 2000_000_000, 1);
        // M0 10K -> S 5K
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user5)), 1000_000_000, 1);
        assertApproxEqAbs(senior.convertToAssets(senior.balanceOf(user6)), 3000_000_000, 1);
        // J0 -> rejected 20K
        assertApproxEqAbs(mockUsdc.balanceOf(bob), 6000 * 1e6, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(carol), 5000 * 1e6, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(david), 5000 * 1e6, 1);
        // M0 -> rejected 5K
        assertApproxEqAbs(mockUsdc.balanceOf(user5), 1000_000_000, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(user6), 3000_000_000, 1);
        // J0 -> rejected 20K +  M0 -> rejected 5K
        // 4000 + 1000
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 5000_000_000, 1);

        assertEq(IPendingPool(lpd.pendingPool).totalSupply(), 0);

        // ### ARRANGE ###

        skip(1 days);
        // # P3 #
        ForceWithdrawalInput[] memory input = new ForceWithdrawalInput[](4);
        input[0] = ForceWithdrawalInput(lpd.tranches[0], user16, 300 * 1e18);
        input[1] = ForceWithdrawalInput(lpd.tranches[0], user17, 600 * 1e18);
        input[2] = ForceWithdrawalInput(lpd.tranches[1], user9, 500 * 1e18);
        input[3] = ForceWithdrawalInput(lpd.tranches[1], user10, 800 * 1e18);
        _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input);
        // total: 2200

        // # P2 #
        _requestWithdrawal(user16, lpd.lendingPool, lpd.tranches[1], 3000 * 1e18);
        _requestWithdrawal(user17, lpd.lendingPool, lpd.tranches[2], 2000 * 1e18);
        _requestWithdrawal(user18, lpd.lendingPool, lpd.tranches[2], 4000 * 1e18);

        // # P1 #
        _requestWithdrawal(user9, lpd.lendingPool, lpd.tranches[1], 1000 * 1e18);
        _requestWithdrawal(user10, lpd.lendingPool, lpd.tranches[1], 200 * 1e18);
        _requestWithdrawal(user11, lpd.lendingPool, lpd.tranches[1], 1800 * 1e18);

        // # P0 #
        _requestWithdrawal(user5, lpd.lendingPool, lpd.tranches[2], 1000 * 1e18);
        _requestWithdrawal(user6, lpd.lendingPool, lpd.tranches[2], 2000 * 1e18);

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);
        userManager.batchCalculateUserLoyaltyLevels(10);

        // ### ACT ###
        uint256 currentEpoch2 = systemVariables.getCurrentEpochNumber();
        ClearingConfiguration memory clearingConfiguration2 =
            ClearingConfiguration(0, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch2, clearingConfiguration2);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch2, type(uint256).max, type(uint256).max);

        // ### ASSERT ###

        // accepted: 1000
        // P3 total: 2200, accepted: 2200, left: 7800,
        // P2 total: 9000, accepted: 7800, left: 0

        // P3
        assertApproxEqAbs(mockUsdc.balanceOf(user9), 500 * 1e6, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(user10), 800 * 1e6, 1);

        // P3 + P2
        // 300 + (7800/9000)*3000=2600
        assertApproxEqAbs(mockUsdc.balanceOf(user16), 2900 * 1e6, 1);
        // 600 + (7800/9000)*2000=23333,333
        assertApproxEqAbs(mockUsdc.balanceOf(user17), 2333333333, 1);

        // P2
        // (7800/9000)*4000=3466,666
        assertApproxEqAbs(mockUsdc.balanceOf(user18), 3466666666, 1);
    }

    function test_doClearing_noUserRequests() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);

        // ### ACT ###
        uint256 currentEpoch1 = systemVariables.getCurrentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;
        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(0, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch1, clearingConfiguration1);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 10, 10);
    }

    function test_doClearing_zeroBatch() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);

        // ### ACT ###
        uint256 currentEpoch1 = systemVariables.getCurrentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;
        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(0, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch1, clearingConfiguration1);

        vm.expectRevert(abi.encodeWithSelector(BatchSizeShouldNotBeZero.selector));
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 0, 0);
    }

    function test_doClearing_noUserRequests_maxBatchSize() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(10);

        // ### ACT ###
        uint256 currentEpoch1 = systemVariables.getCurrentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;
        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(0, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch1, clearingConfiguration1);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, type(uint256).max, type(uint256).max);
    }

    function test_applyInterests() public {
        // ### ARRANGE ###
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // set interest rates to 0%
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 1);

        // deposit requests: total 100K
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
        // S2: 35K
        _requestDeposit(user17, lpd.lendingPool, lpd.tranches[2], 6_000 * 1e6);
        _requestDeposit(user18, lpd.lendingPool, lpd.tranches[2], 4_000 * 1e6);
        _requestDeposit(user19, lpd.lendingPool, lpd.tranches[2], 10_000 * 1e6);
        _requestDeposit(user20, lpd.lendingPool, lpd.tranches[2], 15_000 * 1e6);

        // loyalty levels config: 0-1%: 0, 1%-3%:1, 3%+: 2
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

        // update interest rates to 1% for the epoch after the next one
        vm.startPrank(lendingPoolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], INTEREST_RATE_FULL_PERCENT / 100);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], INTEREST_RATE_FULL_PERCENT / 200);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[2], INTEREST_RATE_FULL_PERCENT / 400);
        vm.stopPrank();

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(30);

        uint256 currentEpoch1 = systemVariables.getCurrentEpochNumber();

        // ### ACT ###
        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 30_00;
        trancheDesiredRatios[2] = 50_00;

        ClearingConfiguration memory clearingConfiguration1 =
            ClearingConfiguration(100_000 * 1e6, trancheDesiredRatios, 10_00, 0, true);
        lendingPoolManager.registerClearingConfig(lpd.lendingPool, currentEpoch1, clearingConfiguration1);

        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1, 30, 30);

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(30);

        // users should get interests
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1 + 1, 30, 30);

        // ### ASSERT ###

        PoolConfiguration memory poolConfiguration = ILendingPool(lpd.lendingPool).poolConfiguration();

        uint256[] memory trancheInterestRatesMultiplier = new uint256[](3);

        {
            uint256 performanceFee = systemVariables.performanceFee();
            trancheInterestRatesMultiplier[0] = (
                poolConfiguration.tranches[0].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
            trancheInterestRatesMultiplier[1] = (
                poolConfiguration.tranches[1].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
            trancheInterestRatesMultiplier[2] = (
                poolConfiguration.tranches[2].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
        }

        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 10_000 * 1e6, 2);

        // ## Assert tranche balance ##
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[0]),
            20_000 * 1e6 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[1]),
            30_000 * 1e6 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[2]),
            60_000 * 1e6 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );

        // ## Assert user balance per tranche ##
        // algo: J2J1J0 M2J2M1J1M0J0 S2M2J2S1M1J1S0M0J0
        ILendingPoolTranche junior = ILendingPoolTranche(lpd.tranches[0]);
        ILendingPoolTranche mezzo = ILendingPoolTranche(lpd.tranches[1]);
        ILendingPoolTranche senior = ILendingPoolTranche(lpd.tranches[2]);

        // # P2 #
        // J2 30K -> J 20K
        assertApproxEqAbs(
            junior.convertToAssets(junior.balanceOf(user16)),
            5333_333_333 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            junior.convertToAssets(junior.balanceOf(user17)),
            4666_666_666 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            junior.convertToAssets(junior.balanceOf(user18)),
            8000_000_000 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            junior.convertToAssets(junior.balanceOf(user19)),
            2000_000_000 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // M2 5K -> M 5K,  J2 30K -> M 10K
        // 2000 + 2666
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user16)),
            4666_666_666 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // 3000 + 1000
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user19)),
            4000_000_000 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // S2 35K -> S 35K
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user17)),
            6000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user18)),
            4000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user19)),
            10000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user20)),
            15000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );

        // # P1 #
        // M1 25K -> M 15K
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user9)),
            3600_000_000 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user10)),
            1200_000_000 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user11)),
            4800_000_000 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            mezzo.convertToAssets(mezzo.balanceOf(user12)),
            5400_000_000 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // M1 25K -> S 10K
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user9)),
            2400_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user10)),
            800_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user11)),
            3200_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user12)),
            3600_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );

        // # P0 #
        // S0 10K -> S 10K
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(david)),
            1000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user7)),
            5000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user8)),
            3000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // S0 10K -> S 10K + M0 10K -> S 5K
        // 1000 + 1000
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(alice)),
            2000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        // M0 10K -> S 5K
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user5)),
            1000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            senior.convertToAssets(senior.balanceOf(user6)),
            3000_000_000 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );

        // ### ACT ###
        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(30);

        // users should get interests
        lendingPoolManager.doClearing(lpd.lendingPool, currentEpoch1 + 2, 30, 30);

        // ### ASSERT ###

        uint256[] memory trancheInterestRatesMultiplier2 = new uint256[](3);
        {
            uint256 performanceFee = systemVariables.performanceFee();
            trancheInterestRatesMultiplier2[0] = (
                poolConfiguration.tranches[0].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
            trancheInterestRatesMultiplier2[1] = (
                poolConfiguration.tranches[1].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
            trancheInterestRatesMultiplier2[2] = (
                poolConfiguration.tranches[2].interestRate * (FULL_PERCENT - performanceFee) / FULL_PERCENT
            ) + INTEREST_RATE_FULL_PERCENT;
        }

        assertEq(poolConfiguration.tranches[0].interestRate, INTEREST_RATE_FULL_PERCENT / 100);
        assertEq(poolConfiguration.tranches[1].interestRate, INTEREST_RATE_FULL_PERCENT / 200);
        assertEq(poolConfiguration.tranches[2].interestRate, INTEREST_RATE_FULL_PERCENT / 400);

        // ## Assert tranche balance including yield ##
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[0]),
            (20_000 * 1e6 * trancheInterestRatesMultiplier[0] / INTEREST_RATE_FULL_PERCENT)
                * trancheInterestRatesMultiplier2[0] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[1]),
            (30_000 * 1e6 * trancheInterestRatesMultiplier[1] / INTEREST_RATE_FULL_PERCENT)
                * trancheInterestRatesMultiplier2[1] / INTEREST_RATE_FULL_PERCENT,
            1
        );
        assertApproxEqAbs(
            lendingPool.balanceOf(lpd.tranches[2]),
            (60_000 * 1e6 * trancheInterestRatesMultiplier[2] / INTEREST_RATE_FULL_PERCENT)
                * trancheInterestRatesMultiplier2[2] / INTEREST_RATE_FULL_PERCENT,
            1
        );
    }
}
