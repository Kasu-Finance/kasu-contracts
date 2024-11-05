// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract FixedTermDepositTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_fixedTermDepositConfiguration() public {
        uint256 interestRate_0_1_percent = INTEREST_RATE_FULL_PERCENT / 1000;

        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        vm.startPrank(poolManagerAccount);
        uint256 configId1 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[1], 4, interestRate_0_1_percent, false
        );

        FixedTermDepositConfig memory ftdConfig1 =
            fixedTermDeposit.lendingPoolFixedTermConfig(lpd.lendingPool, configId1);

        assertEq(configId1, 1);
        assertEq(ftdConfig1.tranche, lpd.tranches[1]);
        assertEq(ftdConfig1.epochInterestRate, interestRate_0_1_percent);
        assertEq(ftdConfig1.epochLockDuration, 4);
        assertEq(uint256(ftdConfig1.fixedTermDepositStatus), uint256(FixedTermDepositStatus.EVERYONE));

        uint256 configId2 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 5, interestRate_0_1_percent * 2, true
        );

        FixedTermDepositConfig memory ftdConfig2 =
            fixedTermDeposit.lendingPoolFixedTermConfig(lpd.lendingPool, configId2);

        assertEq(configId2, 2);
        assertEq(ftdConfig2.tranche, lpd.tranches[2]);
        assertEq(ftdConfig2.epochInterestRate, interestRate_0_1_percent * 2);
        assertEq(ftdConfig2.epochLockDuration, 5);
        assertEq(uint256(ftdConfig2.fixedTermDepositStatus), uint256(FixedTermDepositStatus.WHITELISTED_ONLY));

        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, configId1, FixedTermDepositStatus.DISABLED
        );

        ftdConfig1 = fixedTermDeposit.lendingPoolFixedTermConfig(lpd.lendingPool, configId1);
        assertEq(uint256(ftdConfig1.fixedTermDepositStatus), uint256(FixedTermDepositStatus.DISABLED));

        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, configId2, FixedTermDepositStatus.WHITELISTED_ONLY
        );

        ftdConfig2 = fixedTermDeposit.lendingPoolFixedTermConfig(lpd.lendingPool, configId2);
        assertEq(uint256(ftdConfig2.fixedTermDepositStatus), uint256(FixedTermDepositStatus.WHITELISTED_ONLY));

        LendingPoolWithdrawalConfiguration memory withdrawalConfig =
            fixedTermDeposit.lendingPoolWithdrawalConfiguration(lpd.lendingPool);

        assertEq(withdrawalConfig.requestEpochsInAdvance, 0);
        assertEq(withdrawalConfig.cancelRequestEpochsInAdvance, 0);

        lendingPoolManager.updateLendingPoolWithdrawalConfiguration(
            lpd.lendingPool, LendingPoolWithdrawalConfiguration(2, 1)
        );

        withdrawalConfig = fixedTermDeposit.lendingPoolWithdrawalConfiguration(lpd.lendingPool);

        assertEq(withdrawalConfig.requestEpochsInAdvance, 2);
        assertEq(withdrawalConfig.cancelRequestEpochsInAdvance, 1);

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.updateLendingPoolWithdrawalConfiguration(
            lpd.lendingPool, LendingPoolWithdrawalConfiguration(2, 3)
        );

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, 0, FixedTermDepositStatus.WHITELISTED_ONLY
        );

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, 3, FixedTermDepositStatus.WHITELISTED_ONLY
        );

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 0, interestRate_0_1_percent * 2, true
        );

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(lpd.lendingPool, lpd.tranches[2], 4, 0, true);

        uint256 maxInterestRate = systemVariables.maxTrancheInterestRate();
        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 4, maxInterestRate + 1, true
        );

        vm.expectRevert(abi.encodeWithSelector(ILendingPoolErrors.InvalidTranche.selector, lpd.lendingPool, configId1));
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(lpd.lendingPool, address(1), 4, 1, true);
    }

    function test_fixedTermDeposit_depositAllowance() public {
        // ### ARRANGE ###
        uint256 interestRate_0_1_percent = INTEREST_RATE_FULL_PERCENT / 1000;

        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        vm.startPrank(poolManagerAccount);
        uint256 configId1 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[1], 4, interestRate_0_1_percent, false
        );

        uint256 configId2 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 5, interestRate_0_1_percent * 2, true
        );

        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, configId1, FixedTermDepositStatus.WHITELISTED_ONLY
        );

        vm.startPrank(alice);
        deal(address(mockUsdc), alice, 1_000_000 * 1e6, true);
        mockUsdc.approve(address(lendingPoolManager), type(uint256).max);

        vm.startPrank(poolManagerAccount);
        address[] memory allowlist = new address[](3);
        allowlist[0] = alice;
        allowlist[1] = bob;
        allowlist[2] = carol;

        bool[] memory allowlistStatus = new bool[](3);
        allowlistStatus[0] = true;
        allowlistStatus[1] = true;
        allowlistStatus[2] = true;

        lendingPoolManager.updateFixedTermDepositAllowlist(lpd.lendingPool, configId2, allowlist, allowlistStatus);

        // ### ACT ###
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.UserNotWhitelistedForFixedTermDeposit.selector, lpd.lendingPool, configId1, alice
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 100 * 1e6, "", configId1, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.InvalidTrancheForFixedTermDeposit.selector,
                lpd.lendingPool,
                configId2,
                lpd.tranches[2],
                lpd.tranches[1]
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 100 * 1e6, "", configId2, "");

        vm.expectRevert(InvalidConfiguration.selector);
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[2], 100 * 1e6, "", 3, "");

        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[2], 100 * 1e6, "", configId2, "");

        // ### ARRANGE ###
        vm.startPrank(poolManagerAccount);
        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, configId2, FixedTermDepositStatus.DISABLED
        );

        // ### ACT ###
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IFixedTermDeposit.FixedTermDepositDisabled.selector, lpd.lendingPool, configId2)
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 100 * 1e6, "", configId2, "");

        // ### ARRANGE ###
        vm.startPrank(poolManagerAccount);
        allowlistStatus[0] = false;
        lendingPoolManager.updateFixedTermDepositAllowlist(lpd.lendingPool, configId2, allowlist, allowlistStatus);

        lendingPoolManager.updateLendingPoolTrancheFixedInterestStatus(
            lpd.lendingPool, configId2, FixedTermDepositStatus.WHITELISTED_ONLY
        );

        // ### ACT ###
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.UserNotWhitelistedForFixedTermDeposit.selector, lpd.lendingPool, configId2, alice
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[2], 100 * 1e6, "", configId2, "");

        // ### ASSERT ###
        assertFalse(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId1, alice));
        assertFalse(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId1, bob));
        assertFalse(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId1, carol));

        assertFalse(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId2, alice));
        assertTrue(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId2, bob));
        assertTrue(fixedTermDeposit.fixedTermDepositsAllowlist(lpd.lendingPool, configId2, carol));

        vm.startPrank(poolManagerAccount);
        vm.expectRevert(InvalidArrayLength.selector);
        lendingPoolManager.updateFixedTermDepositAllowlist(lpd.lendingPool, configId2, allowlist, new bool[](0));
    }

    function test_fixedTermDeposit_edgeCases() public {
        // ### ARRANGE ###
        // skip first epoch
        skip(1 weeks);

        uint256 interestRate_0_1_percent = INTEREST_RATE_FULL_PERCENT / 1000;

        LendingPoolDeployment memory lpd;
        {
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
            lpd = _createLendingPoolFromConfig(createPoolConfig);
        }

        vm.startPrank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);
        vm.stopPrank();

        vm.startPrank(poolManagerAccount);
        uint256 configId1 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 4, interestRate_0_1_percent * 2, false
        );
        uint256 configId2 = lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 4, interestRate_0_1_percent / 2, false
        );

        lendingPoolManager.updateLendingPoolWithdrawalConfiguration(
            lpd.lendingPool, LendingPoolWithdrawalConfiguration(2, 1)
        );
        vm.stopPrank();

        // ### ACT ###
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[2], 10_000 * 1e6);
        _requestFixedTermDeposit(bob, lpd.lendingPool, lpd.tranches[2], 20_000 * 1e6, configId1);
        _requestFixedTermDeposit(carol, lpd.lendingPool, lpd.tranches[2], 1_000 * 1e6, configId2);
        _requestFixedTermDeposit(david, lpd.lendingPool, lpd.tranches[2], 1_000 * 1e6, configId2);

        vm.startPrank(user5);
        deal(address(mockUsdc), user5, 1_000_000 * 1e6, true);
        mockUsdc.approve(address(lendingPoolManager), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.InvalidTrancheForFixedTermDeposit.selector,
                lpd.lendingPool,
                configId1,
                lpd.tranches[2],
                lpd.tranches[1]
            )
        );
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[1], 100, "", configId1, "");

        uint256 nextClearingEpoch = systemVariables.currentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 10_00;
        trancheDesiredRatios[1] = 20_00;
        trancheDesiredRatios[2] = 70_00;

        ClearingConfiguration memory clearingConfiguration =
            ClearingConfiguration(32_000 * 1e6, trancheDesiredRatios, 0, 0);

        // move to clearing period
        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            true
        );
        nextClearingEpoch++;

        {
            uint256[] memory ftdIds = fixedTermDeposit.lendingPoolFixedTermDepositIds(lpd.lendingPool);

            assertEq(ftdIds.length, 3);
            assertEq(ftdIds[0], 0);
            assertEq(ftdIds[1], 1);
            assertEq(ftdIds[2], 2);
        }

        // move to start of next epoch
        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        vm.startPrank(david);
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.FixedTermDepositWithdrawalAlreadyRequested.selector, lpd.lendingPool, 0
            )
        );
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.InvalidLendingPoolFixedTermDepositUser.selector, lpd.lendingPool, 1, david
            )
        );
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IFixedTermDeposit.InvalidFixedTermDepositId.selector, lpd.lendingPool, 3)
        );
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 3);
        vm.stopPrank();

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.FixedTermDepositWithdrawalRequestTooLate.selector, lpd.lendingPool, 1, 2, 5, 4
            )
        );
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.FixedTermDepositWithdrawalNotRequested.selector, lpd.lendingPool, 1
            )
        );
        lendingPoolManager.cancelFixedTermDepositWithdrawalRequest(lpd.lendingPool, 1);
        vm.stopPrank();

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        vm.startPrank(david);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.FixedTermDepositWithdrawalRequestCancelTooLate.selector, lpd.lendingPool, 0, 1, 5, 5
            )
        );
        lendingPoolManager.cancelFixedTermDepositWithdrawalRequest(lpd.lendingPool, 0);
        vm.stopPrank();

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.endFixedTermDeposit(lpd.lendingPool, 0, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IFixedTermDeposit.InvalidFixedTermDepositId.selector, lpd.lendingPool, 0)
        );
        lendingPoolManager.endFixedTermDeposit(lpd.lendingPool, 0, 1);

        assertGt(ILendingPoolTranche(lpd.tranches[2]).balanceOf(david), 0);

        skip(9 days);

        vm.startPrank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(
                IFixedTermDeposit.FixedTermDepositWithdrawalRequestTooLate.selector, lpd.lendingPool, 1, 2, 5, 6
            )
        );
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 1);
        vm.stopPrank();

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // ### ASSERT ###
        assertGt(ILendingPoolTranche(lpd.tranches[2]).balanceOf(alice), 0);
        assertGt(ILendingPoolTranche(lpd.tranches[2]).balanceOf(bob), 0);
        assertGt(ILendingPoolTranche(lpd.tranches[2]).balanceOf(carol), 0);

        assertEq(fixedTermDeposit.lendingPoolFixedTermDepositsCount(lpd.lendingPool), 0);

        uint256 clearingsCount = 4;
        uint256 userBalanceSum;
        uint256 feesPaidSum;

        {
            (uint256 aliceBalance, uint256 aliceFeesPaid) =
                _calculateUserBalanceAfterInterests(10_000 * 1e6, interestRate_0_1_percent, clearingsCount, 10_00);
            assertApproxEqAbs(ILendingPool(lpd.lendingPool).userBalance(alice), aliceBalance, clearingsCount);

            userBalanceSum += aliceBalance;
            feesPaidSum += aliceFeesPaid;
        }

        {
            (uint256 bobBalance, uint256 bobFeesPaid) =
                _calculateUserBalanceAfterInterests(20_000 * 1e6, interestRate_0_1_percent * 2, clearingsCount, 10_00);
            assertApproxEqAbs(ILendingPool(lpd.lendingPool).userBalance(bob), bobBalance, clearingsCount);

            userBalanceSum += bobBalance;
            feesPaidSum += bobFeesPaid;
        }

        {
            (uint256 carolBalance, uint256 carolFeesPaid) =
                _calculateUserBalanceAfterInterests(1_000 * 1e6, interestRate_0_1_percent / 2, clearingsCount, 10_00);
            assertApproxEqAbs(ILendingPool(lpd.lendingPool).userBalance(carol), carolBalance, clearingsCount);

            userBalanceSum += carolBalance;
            feesPaidSum += carolFeesPaid;
        }

        {
            (uint256 davidBalance, uint256 davidFeesPaid) = _calculateUserBalanceAfterInterests(
                1_000 * 1e6, interestRate_0_1_percent / 2, clearingsCount - 1, 10_00
            );

            (uint256 davidBalance2, uint256 davidFeesPaid2) =
                _calculateUserBalanceAfterInterests(davidBalance, interestRate_0_1_percent, 1, 10_00);
            assertApproxEqAbs(ILendingPool(lpd.lendingPool).userBalance(david), davidBalance2, clearingsCount);

            userBalanceSum += davidBalance2;
            feesPaidSum += davidFeesPaid + davidFeesPaid2;
        }

        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), userBalanceSum, clearingsCount * 4);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).feesOwedAmount(), feesPaidSum, clearingsCount * 4);

        skip(1 weeks);
        vm.startPrank(david);
        uint256 davidShares = ILendingPoolTranche(lpd.tranches[2]).balanceOf(david);
        vm.expectRevert(ILendingPoolErrors.ClearingIsPending.selector);
        lendingPoolManager.lockDepositForFixedTerm(lpd.lendingPool, lpd.tranches[2], davidShares, configId1);

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        vm.startPrank(david);
        lendingPoolManager.lockDepositForFixedTerm(lpd.lendingPool, lpd.tranches[2], davidShares, configId1);

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.endFixedTermDeposit(lpd.lendingPool, 3, type(uint256).max);

        vm.startPrank(david);
        lendingPoolManager.lockDepositForFixedTerm(lpd.lendingPool, lpd.tranches[2], davidShares, configId1);

        UserLendingPoolFixedTermDeposit memory ftd = fixedTermDeposit.lendingPoolFixedTermDeposit(lpd.lendingPool, 4);

        assertEq(ftd.user, david);
        assertEq(ftd.fixedTermDepositConfigId, configId1);
        assertEq(ftd.epochLockNumber, systemVariables.currentEpochNumber());
        assertEq(ftd.epochUnlockNumber, systemVariables.currentEpochNumber() + 4);
        assertEq(ftd.withdrawRequested, false);
        assertEq(ftd.trancheShares, davidShares);

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.endFixedTermDeposit(lpd.lendingPool, 4, 0);
    }

    struct Balances {
        uint256[][] trancheUser;
        uint256 feesOwed;
        uint256 feesPaid;
    }

    function test_fixedTermDeposit_checkInterests() public {
        // ### ARRANGE ###
        // skip first epoch
        skip(1 weeks);

        uint256 interestRate_0_1_percent = INTEREST_RATE_FULL_PERCENT / 1000;
        uint256 interestRate_0_11_percent = interestRate_0_1_percent + INTEREST_RATE_FULL_PERCENT / 10000;

        uint256[3] memory baseInterestRates =
            [interestRate_0_1_percent * 3, interestRate_0_1_percent * 2, interestRate_0_1_percent];
        uint256[3] memory baseInterestRatesAfter =
            [interestRate_0_1_percent * 4, interestRate_0_1_percent * 3, interestRate_0_1_percent * 2];
        uint256[3] memory fixedTermInterestRates =
            [interestRate_0_11_percent * 3, interestRate_0_11_percent * 2, interestRate_0_11_percent];

        Balances memory balances;
        balances.trancheUser = new uint256[][](3);
        balances.trancheUser[0] = new uint256[](6);
        balances.trancheUser[1] = new uint256[](6);
        balances.trancheUser[2] = new uint256[](6);

        LendingPoolDeployment memory lpd;
        {
            CreateTrancheConfig[] memory tranches = new CreateTrancheConfig[](3);
            tranches[0] = CreateTrancheConfig(10_00, baseInterestRates[0], 0, type(uint256).max);
            tranches[1] = CreateTrancheConfig(20_00, baseInterestRates[1], 0, type(uint256).max);
            tranches[2] = CreateTrancheConfig(70_00, baseInterestRates[2], 0, type(uint256).max);
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
            lpd = _createLendingPoolFromConfig(createPoolConfig);
        }

        vm.startPrank(admin);
        lendingPoolManager.updateTrancheInterestRateChangeEpochDelay(lpd.lendingPool, 0);
        vm.stopPrank();

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[0], 5, fixedTermInterestRates[0], false
        );
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[1], 5, fixedTermInterestRates[1], false
        );
        lendingPoolManager.addLendingPoolTrancheFixedTermDeposit(
            lpd.lendingPool, lpd.tranches[2], 5, fixedTermInterestRates[2], false
        );
        vm.stopPrank();

        // ### ACT ###
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 15_000 * 1e6);
        _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 5_000 * 1e6);
        _requestDeposit(carol, lpd.lendingPool, lpd.tranches[2], 50_000 * 1e6);
        _requestFixedTermDeposit(david, lpd.lendingPool, lpd.tranches[0], 15_000 * 1e6, 1);
        _requestFixedTermDeposit(user5, lpd.lendingPool, lpd.tranches[1], 5_000 * 1e6, 2);
        _requestFixedTermDeposit(user6, lpd.lendingPool, lpd.tranches[2], 10_000 * 1e6, 3);

        uint256 nextClearingEpoch = systemVariables.currentEpochNumber();

        uint256[] memory trancheDesiredRatios = new uint256[](3);
        trancheDesiredRatios[0] = 10_00;
        trancheDesiredRatios[1] = 20_00;
        trancheDesiredRatios[2] = 70_00;

        ClearingConfiguration memory clearingConfiguration =
            ClearingConfiguration(100_000 * 1e6, trancheDesiredRatios, 0, 0);

        // move to clearing period
        skip(6 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            true
        );
        nextClearingEpoch++;

        // alice
        balances.trancheUser[0][0] = 5_000 * 1e6;
        balances.trancheUser[1][0] = 5_000 * 1e6;
        balances.trancheUser[2][0] = 5_000 * 1e6;

        // bob
        balances.trancheUser[1][1] = 5_000 * 1e6;

        // carol
        balances.trancheUser[2][2] = 50_000 * 1e6;

        // david
        balances.trancheUser[0][3] = 5_000 * 1e6;
        balances.trancheUser[1][3] = 5_000 * 1e6;
        balances.trancheUser[2][3] = 5_000 * 1e6;

        // user5
        balances.trancheUser[1][4] = 5_000 * 1e6;

        // user6
        balances.trancheUser[2][5] = 10_000 * 1e6;

        // move to start of next epoch
        skip(7 days);
        assertEq(
            uint256(fixedTermDeposit.fixedTermDepositsClearingPerEpochStatus(lpd.lendingPool, nextClearingEpoch)),
            uint256(TaskStatus.UNINITIALIZED)
        );

        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            1,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );

        assertEq(
            uint256(fixedTermDeposit.fixedTermDepositsClearingPerEpochStatus(lpd.lendingPool, nextClearingEpoch)),
            uint256(TaskStatus.PENDING)
        );

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            1,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );

        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            1,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );

        assertEq(
            uint256(fixedTermDeposit.fixedTermDepositsClearingPerEpochStatus(lpd.lendingPool, nextClearingEpoch)),
            uint256(TaskStatus.ENDED)
        );

        nextClearingEpoch++;

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRates[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 3, 0, fixedTermInterestRates[0]);
        _applyUserTrancheInterest(balances, 3, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 4, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 5, 2, fixedTermInterestRates[2]);

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRates[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 3, 0, fixedTermInterestRates[0]);
        _applyUserTrancheInterest(balances, 3, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 4, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 5, 2, fixedTermInterestRates[2]);

        // david locks the mezzanine and senior tokens
        vm.startPrank(david);
        lendingPoolManager.lockDepositForFixedTerm(
            lpd.lendingPool, lpd.tranches[1], ILendingPoolTranche(lpd.tranches[1]).balanceOf(david), 2
        );
        lendingPoolManager.lockDepositForFixedTerm(
            lpd.lendingPool, lpd.tranches[2], ILendingPoolTranche(lpd.tranches[2]).balanceOf(david), 3
        );
        vm.stopPrank();

        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(david), 0);
        assertEq(ILendingPoolTranche(lpd.tranches[2]).balanceOf(david), 0);

        // user5 request FTD withdrawal
        vm.startPrank(user5);
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 1);
        vm.stopPrank();

        // user6 request FTD withdrawal
        vm.startPrank(user6);
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 0);
        vm.stopPrank();

        // david request and cancel FTD withdrawal
        vm.startPrank(david);
        lendingPoolManager.requestFixedTermDepositWithdrawal(lpd.lendingPool, 2);
        lendingPoolManager.cancelFixedTermDepositWithdrawalRequest(lpd.lendingPool, 2);
        vm.stopPrank();

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRates[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRates[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRates[2]);
        _applyUserTrancheInterest(balances, 3, 0, fixedTermInterestRates[0]);
        _applyUserTrancheInterest(balances, 3, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, fixedTermInterestRates[2]);
        _applyUserTrancheInterest(balances, 4, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 5, 2, fixedTermInterestRates[2]);

        vm.startPrank(poolManagerAccount);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[0], baseInterestRatesAfter[0]);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[1], baseInterestRatesAfter[1]);
        lendingPoolManager.updateTrancheInterestRate(lpd.lendingPool, lpd.tranches[2], baseInterestRatesAfter[2]);
        vm.stopPrank();

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 3, 0, fixedTermInterestRates[0]);
        _applyUserTrancheInterest(balances, 3, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, fixedTermInterestRates[2]);
        _applyUserTrancheInterest(balances, 4, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 5, 2, fixedTermInterestRates[2]);

        assertApproxEqAbs(ILendingPool(lpd.lendingPool).feesOwedAmount(), balances.feesOwed, nextClearingEpoch * 6);

        _requestWithdrawal(
            alice, lpd.lendingPool, lpd.tranches[2], ILendingPoolTranche(lpd.tranches[2]).balanceOf(alice)
        );

        _repayOwedFunds(poolFundsManagerAccount, poolFundsManagerAccount, lpd.lendingPool, 16_000 * 1e6);

        balances.feesPaid = balances.feesOwed;

        balances.feesOwed = 0;

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 3, 0, fixedTermInterestRates[0]);
        _applyUserTrancheInterest(balances, 3, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, fixedTermInterestRates[2]);
        _applyUserTrancheInterest(balances, 4, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 5, 2, fixedTermInterestRates[2]);

        assertApproxEqAbs(mockUsdc.balanceOf(user5), balances.trancheUser[1][4], nextClearingEpoch);
        assertApproxEqAbs(mockUsdc.balanceOf(user6), balances.trancheUser[2][5], nextClearingEpoch);

        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(user5), 0);
        assertEq(ILendingPoolTranche(lpd.tranches[2]).balanceOf(user6), 0);

        assertEq(ILendingPool(lpd.lendingPool).userBalance(user5), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(user6), 0);

        {
            uint256 excessLeft =
                16_000 * 1e6 - balances.trancheUser[1][4] - balances.trancheUser[2][5] - balances.feesPaid;
            assertApproxEqAbs(mockUsdc.balanceOf(alice), excessLeft, nextClearingEpoch);
            balances.trancheUser[2][0] = balances.trancheUser[2][0] - excessLeft;

            deal(address(mockUsdc), alice, 0, true);
        }

        balances.trancheUser[1][4] = 0;
        balances.trancheUser[2][5] = 0;

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        assertEq(ILendingPoolTranche(lpd.tranches[1]).balanceOf(david), 0);
        assertEq(ILendingPoolTranche(lpd.tranches[2]).balanceOf(david), 0);

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 3, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 3, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, fixedTermInterestRates[2]);

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        assertGt(ILendingPoolTranche(lpd.tranches[1]).balanceOf(david), 0);
        assertGt(ILendingPoolTranche(lpd.tranches[2]).balanceOf(david), 0);

        // apply user interests
        _applyUserTrancheInterest(balances, 0, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 0, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 0, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 1, 1, baseInterestRatesAfter[1]);
        _applyUserTrancheInterest(balances, 2, 2, baseInterestRatesAfter[2]);
        _applyUserTrancheInterest(balances, 3, 0, baseInterestRatesAfter[0]);
        _applyUserTrancheInterest(balances, 3, 1, fixedTermInterestRates[1]);
        _applyUserTrancheInterest(balances, 3, 2, fixedTermInterestRates[2]);

        // withdraw all
        _requestWithdrawal(
            alice, lpd.lendingPool, lpd.tranches[0], ILendingPoolTranche(lpd.tranches[0]).balanceOf(alice)
        );
        _requestWithdrawal(
            alice, lpd.lendingPool, lpd.tranches[1], ILendingPoolTranche(lpd.tranches[1]).balanceOf(alice)
        );
        _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], ILendingPoolTranche(lpd.tranches[1]).balanceOf(bob));
        _requestWithdrawal(
            carol, lpd.lendingPool, lpd.tranches[2], ILendingPoolTranche(lpd.tranches[2]).balanceOf(carol)
        );
        _requestWithdrawal(
            david, lpd.lendingPool, lpd.tranches[0], ILendingPoolTranche(lpd.tranches[0]).balanceOf(david)
        );
        _requestWithdrawal(
            david, lpd.lendingPool, lpd.tranches[1], ILendingPoolTranche(lpd.tranches[1]).balanceOf(david)
        );
        _requestWithdrawal(
            david, lpd.lendingPool, lpd.tranches[2], ILendingPoolTranche(lpd.tranches[2]).balanceOf(david)
        );

        // repay all

        assertApproxEqAbs(ILendingPool(lpd.lendingPool).feesOwedAmount(), balances.feesOwed, nextClearingEpoch * 6);

        _repayOwedFunds(
            poolFundsManagerAccount,
            poolFundsManagerAccount,
            lpd.lendingPool,
            ILendingPool(lpd.lendingPool).feesOwedAmount() + ILendingPool(lpd.lendingPool).userOwedAmount()
        );

        // stop the pool
        _stop(poolManagerAccount, lpd.lendingPool);

        skip(7 days);
        userManager.batchCalculateUserLoyaltyLevels(type(uint256).max);
        _doClearing(
            poolClearingManagerAccount,
            lpd.lendingPool,
            nextClearingEpoch,
            type(uint256).max,
            type(uint256).max,
            clearingConfiguration,
            false
        );
        nextClearingEpoch++;

        // ### ASSERT ###

        assertEq(ILendingPool(lpd.lendingPool).userBalance(alice), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(bob), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(carol), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(david), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(user5), 0);
        assertEq(ILendingPool(lpd.lendingPool).userBalance(user6), 0);

        assertEq(ILendingPool(lpd.lendingPool).feesOwedAmount(), 0);
        assertEq(ILendingPool(lpd.lendingPool).userOwedAmount(), 0);
        assertApproxEqAbs(ILendingPool(lpd.lendingPool).totalSupply(), 0, 6);

        assertEq(ILendingPoolTranche(lpd.tranches[0]).totalSupply(), 0);
        assertEq(ILendingPoolTranche(lpd.tranches[1]).totalSupply(), 0);
        assertEq(ILendingPoolTranche(lpd.tranches[2]).totalSupply(), 0);

        assertApproxEqAbs(
            mockUsdc.balanceOf(alice),
            balances.trancheUser[2][0] + balances.trancheUser[1][0] + balances.trancheUser[0][0],
            nextClearingEpoch * 3
        );
        assertApproxEqAbs(mockUsdc.balanceOf(bob), balances.trancheUser[1][1], nextClearingEpoch);
        assertApproxEqAbs(mockUsdc.balanceOf(carol), balances.trancheUser[2][2], nextClearingEpoch);
        assertApproxEqAbs(
            mockUsdc.balanceOf(david),
            balances.trancheUser[0][3] + balances.trancheUser[1][3] + balances.trancheUser[2][3],
            nextClearingEpoch
        );
    }

    function _calculateUserBalanceAfterInterests(
        uint256 amountDeposited,
        uint256 epochInterestRate,
        uint256 epochs,
        uint256 interestFees
    ) private pure returns (uint256 amountAfterInterests, uint256 feesOwed) {
        amountAfterInterests = amountDeposited;
        for (uint256 i; i < epochs; i++) {
            uint256 interestPaid = (amountAfterInterests * epochInterestRate) / INTEREST_RATE_FULL_PERCENT;
            uint256 feeOwed = interestPaid * interestFees / FULL_PERCENT;
            feesOwed += feeOwed;
            amountAfterInterests += interestPaid - feeOwed;
        }
    }

    function _applyUserTrancheInterest(
        Balances memory balances,
        uint256 userIndex,
        uint256 trancheIndex,
        uint256 interestRate
    ) private pure {
        (uint256 amountAfterInterests, uint256 feesOwed) =
            _calculateUserBalanceAfterInterests(balances.trancheUser[trancheIndex][userIndex], interestRate, 1, 10_00);
        balances.trancheUser[trancheIndex][userIndex] = amountAfterInterests;
        balances.feesOwed += feesOwed;
    }
}
