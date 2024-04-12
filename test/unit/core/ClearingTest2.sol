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
    }

    function test_clearing_lendingPoolTwoTranches() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
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

        // M: 15K
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

        // ## lending pool balances
        // excess is left 0.1 * 1700
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 1_700 * 1e6, 6);

        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);
        // 17000 + 0.1 & 17000
        assertApproxEqAbs(lendingPool.totalSupply(), 18_700 * 1e6, 6);

        // ## tranche balances
        // M: 0.2 * 17000
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[0]), 3_400 * 1e6, 5);
        // S: 0.8 * 17000 + 0.1 * 17000
        assertApproxEqAbs(lendingPool.balanceOf(lpd.tranches[1]), 15_300 * 1e6, 5);

        // ## user tranche1 balances
        ILendingPoolTranche tranche1 = ILendingPoolTranche(lpd.tranches[0]);
        ILendingPoolTranche tranche2 = ILendingPoolTranche(lpd.tranches[1]);

        // M0 15K -> M 3.4: 3400 / 15000 * deposit
        assertApproxEqAbs(tranche1.balanceOf(alice), 226666667000000000000, 3);
        assertApproxEqAbs(tranche1.balanceOf(bob), 453333334000000000000, 3);
        assertApproxEqAbs(tranche1.balanceOf(carol), 1133333334000000000000, 3);
        assertApproxEqAbs(tranche1.balanceOf(david), 113333334000000000000, 3);
        assertApproxEqAbs(tranche1.balanceOf(user5), 566666667000000000000, 3);
        assertApproxEqAbs(tranche1.balanceOf(user6), 906666667000000000000, 3);

        // S0 12k -> S 15.3K
        assertApproxEqAbs(tranche2.balanceOf(user7), 4_000 * 1e18, 3);
        assertApproxEqAbs(tranche2.balanceOf(user8), 2_000 * 1e18, 3);
        assertApproxEqAbs(tranche2.balanceOf(user9), 5_000 * 1e18, 3);
        assertApproxEqAbs(tranche2.balanceOf(user10), 1_000 * 1e18, 3);

        // M0 15K -> S 15.3K - 12K = 3.3k : 3.3K / 15K * deposit
        assertApproxEqAbs(tranche2.balanceOf(alice), 220000000000000000000, 3);
        assertApproxEqAbs(tranche2.balanceOf(bob), 440000000000000000000, 3);
        assertApproxEqAbs(tranche2.balanceOf(carol), 1100000000000000000000, 3);
        assertApproxEqAbs(tranche2.balanceOf(david), 110000000000000000000, 3);
        assertApproxEqAbs(tranche2.balanceOf(user5), 550000000000000000000, 3);
        assertApproxEqAbs(tranche2.balanceOf(user6), 880000000000000000000, 3);
    }

    function test_case1() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 10_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](3);
        createTrancheConfig[0] = CreateTrancheConfig(40_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(60_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[2] = CreateTrancheConfig(0, 2500000000000000, minDepositAmount, maxDepositAmount);
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

        vm.prank(poolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], 0);

        // user requests: total 15K
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 1_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[0], 2_000 * 1e6);
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[0], 5_000 * 1e6);
        _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 500 * 1e6);
        _requestDeposit(user5, lpd.lendingPool, lpd.tranches[0], 2_500 * 1e6);
        _requestDeposit(user6, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);

        skip(6 days);

        userManager.batchCalculateUserLoyaltyLevels(20);

        // ### ACT ###

        ClearingConfiguration memory clearingConfiguration;

        uint256 currentEpoch = systemVariables.currentEpochNumber();

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
        ILendingPool lendingPool = ILendingPool(lpd.lendingPool);

        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 10_000 * 1e6, 6);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), 10_000 * 1e6, 6);
    }

    function test_case2() public {
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 10_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](3);
        createTrancheConfig[0] = CreateTrancheConfig(0, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(100_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[2] = CreateTrancheConfig(0, 2500000000000000, minDepositAmount, maxDepositAmount);
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
    }
}
