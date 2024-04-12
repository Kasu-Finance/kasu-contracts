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
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 10_000 * 1e6, 6);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), 10_000 * 1e6, 6);
    }

    function test_clearing_lendingPoolTwoTranches() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 17_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](2);
        createTrancheConfig[0] = CreateTrancheConfig(20_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(80_00, 2500000000000000, minDepositAmount, maxDepositAmount);
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

        // tranche 2: 12K
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
        assertApproxEqAbs(mockUsdc.balanceOf(lpd.lendingPool), 17_000 * 1e6, 6);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), 17_000 * 1e6, 6);
    }

    function test_case1() public {
        // ### ARRANGE ###
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 10_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](3);
        createTrancheConfig[0] = CreateTrancheConfig(100_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(0, 2500000000000000, minDepositAmount, maxDepositAmount);
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
}
