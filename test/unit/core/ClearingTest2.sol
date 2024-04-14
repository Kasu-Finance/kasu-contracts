// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract ClearingTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_clearing_lendingPoolOneTranche() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 10_000 * 1e6;

        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](1);
        createTrancheConfig[0] = CreateTrancheConfig(100_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            minExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );

        LendingPoolDeployment memory lpd = _createLendingPoolFromConfig(createPoolConfig);

        // set interest rates to 0%
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], 0);
        vm.stopPrank();

        // tranche 1: 15K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 1_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 2_000 * 1e6);
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 5_000 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 500 * 1e6);
        _requestDeposit(user5, lpd.lendingPool, lpd.tranches[0], 2_500 * 1e6);
        _requestDeposit(user6, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);

        // user loyalty levels
        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);

        // ### ACT ###
        uint256 currentEpoch = systemVariables.currentEpochNumber();
        ClearingConfiguration memory clearingConfiguration;

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            currentEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );

        // ### ASSERT ###
        // 10_000 * 0,1% = 1000
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 1_000 * 1e6, 6);
        // 10_000 + 10_000 * 0,1% = 11000
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), 11_000 * 1e6, 6);

        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        ILendingPoolTranche tranche = ILendingPoolTranche(lpd.tranches[0]);

        // 10_000 + 0.1 * 10_000
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[0]), 11_000 * 1e6, 3);

        // S0: 15K -> S 10K + 0.1 * 10K: 11_000 / 15_000 * 1_000
        assertApproxEqAbs(tranche.balanceOf(alice), 733333334000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(bob), 1466666667000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(carol), 3666666667000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(david), 366666667000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(user5), 1833333334000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(user6), 2933333334000000000000, 3);

        // ### ARRANGE ###
        skip(1 days);

        // request withdrawals
        // J: 100K
        _requestWithdrawal(carol, lpd.lendingPool, lpd.tranches[0], 500 * 1e18);
        _requestWithdrawal(user5, lpd.lendingPool, lpd.tranches[0], 500 * 1e18);

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);

        // ### ACT ###
        uint256[] memory trancheDesiredRatios = new uint256[](1);
        trancheDesiredRatios[0] = 100_00;
        ClearingConfiguration memory clearingConfiguration2 = ClearingConfiguration(0, trancheDesiredRatios, 0, 0);

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            systemVariables.currentEpochNumber(),
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration2,
            true
        );

        // ### ASSERT ###

        // ## lending pool balance
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 0, 3);
        assertApproxEqAbs(lendingPool.totalSupply(), 10_000 * 1e6, 3);

        // user balances
        assertApproxEqAbs(tranche.balanceOf(carol), 3166666667000000000000, 3);
        assertApproxEqAbs(tranche.balanceOf(user5), 1333333334000000000000, 3);
    }

    function test_clearing_lendingPoolTwoTranches() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 5_00;
        uint256 desiredDrawAmount = 17_000 * 1e6;

        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](2);
        createTrancheConfig[0] = CreateTrancheConfig(20_00, 0, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(80_00, 0, minDepositAmount, maxDepositAmount);

        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            minExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );

        LendingPoolDeployment memory lpd = _createLendingPoolFromConfig(createPoolConfig);

        // set interest rates to 0%
        vm.prank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);

        // J: 15K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 1_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 2_000 * 1e6);
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 5_000 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 500 * 1e6);
        _requestDeposit(user5, lpd.lendingPool, lpd.tranches[0], 2_500 * 1e6);
        _requestDeposit(user6, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);

        // S: 12K
        _requestDeposit(user7, lpd.lendingPool, lpd.tranches[1], 4_000 * 1e6);
        _requestDeposit(user8, lpd.lendingPool, lpd.tranches[1], 2_000 * 1e6);
        _requestDeposit(user9, lpd.lendingPool, lpd.tranches[1], 5_000 * 1e6);
        _requestDeposit(user10, lpd.lendingPool, lpd.tranches[1], 1_000 * 1e6);

        // user loyalty levels
        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);

        // ### ACT ###
        ClearingConfiguration memory clearingConfiguration;

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            systemVariables.currentEpochNumber(),
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );

        // ### ASSERT ###

        // ## lending pool balances
        // excess is left 0.1 * 1700
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 1_700 * 1e6, 6);

        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        // 17000 + 0.1 & 17000
        assertApproxEqAbs(lendingPool.totalSupply(), 18_700 * 1e6, 6);

        // ## tranche balances
        // J: 0.2 * 17000
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[0]), 3_400 * 1e6, 5);
        // S: 0.8 * 17000 + 0.1 * 17000
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[1]), 15_300 * 1e6, 5);

        // ## user tranche1 balances
        ILendingPoolTranche juniorTranche = ILendingPoolTranche(lpd.tranches[0]);
        ILendingPoolTranche seniorTranche = ILendingPoolTranche(lpd.tranches[1]);

        // J0 15K -> M 3.4: 3.4K / 15K * deposit
        assertApproxEqAbs(juniorTranche.balanceOf(alice), 226666667000000000000, 3);
        assertApproxEqAbs(juniorTranche.balanceOf(bob), 453333334000000000000, 3);
        assertApproxEqAbs(juniorTranche.balanceOf(carol), 1133333334000000000000, 3);
        assertApproxEqAbs(juniorTranche.balanceOf(david), 113333334000000000000, 3);
        assertApproxEqAbs(juniorTranche.balanceOf(user5), 566666667000000000000, 3);
        assertApproxEqAbs(juniorTranche.balanceOf(user6), 906666667000000000000, 3);

        // S0 12K -> S 15.3K
        assertApproxEqAbs(seniorTranche.balanceOf(user7), 4_000 * 1e18, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user8), 2_000 * 1e18, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user9), 5_000 * 1e18, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user10), 1_000 * 1e18, 3);

        // J0 15K -> S 15.3K - 12K = 3.3k : 3.3K / 15K * deposit
        assertApproxEqAbs(seniorTranche.balanceOf(alice), 220000000000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(bob), 440000000000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(carol), 1100000000000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(david), 110000000000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user5), 550000000000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user6), 880000000000000000000, 3);

        // J0 15K -> rejected 15K - 3.3K - 3.4K = 8.3K : 8.3K / 15K * deposits
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 553333333, 3);
        assertApproxEqAbs(mockUsdc.balanceOf(bob), 1106666666, 3);
        assertApproxEqAbs(mockUsdc.balanceOf(carol), 2766666666, 3);
        assertApproxEqAbs(mockUsdc.balanceOf(david), 276666666, 3);
        assertApproxEqAbs(mockUsdc.balanceOf(user5), 1383333333, 3);
        assertApproxEqAbs(mockUsdc.balanceOf(user6), 2213333333, 3);

        // ### ARRANGE ###
        skip(1 days);

        // request withdrawals
        // J: 0.5K
        _requestWithdrawal(carol, lpd.lendingPool, lpd.tranches[0], 500 * 1e18);

        // S: 1K
        _requestWithdrawal(user8, lpd.lendingPool, lpd.tranches[1], 1_000 * 1e18);

        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);

        // ### ACT ###
        uint256[] memory trancheDesiredRatios = new uint256[](2);
        trancheDesiredRatios[0] = 20_00;
        trancheDesiredRatios[1] = 80_00;
        ClearingConfiguration memory clearingConfiguration2 = ClearingConfiguration(0, trancheDesiredRatios, 0, 0);

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            systemVariables.currentEpochNumber(),
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration2,
            true
        );

        // ### ASSERT ###

        // ## lending pool balance
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 200 * 1e6, 6);
        assertApproxEqAbs(lendingPool.totalSupply(), 17_200 * 1e6, 6);

        // user balances
        assertApproxEqAbs(juniorTranche.balanceOf(carol), 633333334000000000000, 3);
        assertApproxEqAbs(seniorTranche.balanceOf(user8), 1_000 * 1e18, 3);
    }
}
