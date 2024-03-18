// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/core/clearing/AcceptedRequestsCalculation.sol";

contract ClearingCalculationTest is Test {
    AcceptedRequestsCalculation clearingCalculation;

    function setUp() public {
        clearingCalculation = new AcceptedRequestsCalculation();
    }

    function test_doClearing_testDepositsSameAsRatios() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        // new accepted deposit should be 100_000 * 1e6
        // (balance.owed + input.config.borrowAmount) * config.maxExcessPercentage = (950_000 * 1e6 + 100_000 * 1e6) * 10% = 100_000 * 1e6

        // total deposit
        input.pendingDeposits.totalDepositAmount = 100_000 * 1e6;
        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 20_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 30_000 * 1e6; // mezzanine
        input.pendingDeposits.trancheDepositsAmounts[2] = 50_000 * 1e6; // senior
        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 10_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 5_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 5_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // mezzanine priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 10_000 * 1e6; // mezzanine priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 5_000 * 1e6; // mezzanine priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][0] = 25_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][1] = 15_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][2] = 10_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT
        for (uint256 i; i < tranchePriorityDepositsAccepted.length; ++i) {
            for (uint256 j; j < tranchePriorityDepositsAccepted[i].length; ++j) {
                assertEq(
                    tranchePriorityDepositsAccepted[i][j][i], input.pendingDeposits.tranchePriorityDepositsAmounts[i][j]
                );
            }
        }
    }

    function test_doClearing_testDepositsBumpUpDeposits() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        // new accepted deposit should be 100_000 * 1e6
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 100_000 * 1e6 + 100_000 * 1e6 = 100_000 * 1e6

        // total deposit
        input.pendingDeposits.totalDepositAmount = 105_000 * 1e6;
        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 55_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 30_000 * 1e6; // mezzanine
        input.pendingDeposits.trancheDepositsAmounts[2] = 20_000 * 1e6; // senior
        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 25_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 15_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // mezzanine priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 10_000 * 1e6; // mezzanine priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 5_000 * 1e6; // mezzanine priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][0] = 10_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][1] = 5_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][2] = 5_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT in the order as the deposits are accepted
        // junior deposits to junior
        assertEq(tranchePriorityDepositsAccepted[0][2][0], 15_000 * 1e6); // junior priority 2 to junior
        assertEq(tranchePriorityDepositsAccepted[0][1][0], 5_000 * 1e6); // junior priority 1 to junior
        assertEq(tranchePriorityDepositsAccepted[0][0][0], 0); // junior priority 0 to junior

        // deposits to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][2][1], 5_000 * 1e6); // mezzanine priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][2][1], 0); // junior priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][1][1], 10_000 * 1e6); // mezzanine priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][1][1], 10_000 * 1e6); // junior priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][0][1], 5_000 * 1e6); // mezzanine priority 0 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][0][1], 0); // junior priority 0 to mezzanine

        // deposits to senior
        assertEq(tranchePriorityDepositsAccepted[2][2][2], 5_000 * 1e6); // senior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[1][2][2], 0); // mezzanine priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[0][2][2], 0); // junior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[2][1][2], 5_000 * 1e6); // senior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[1][1][2], 0); // mezzanine priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[0][1][2], 0); // junior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[2][0][2], 10_000 * 1e6); // senior priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[1][0][2], 10_000 * 1e6); // mezzanine priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[0][0][2], 20_000 * 1e6); // junior priority 0 to senior

        // ASSERT values that should always be 0
        _assertDepositAcceptedAlwaysZeroValues(tranchePriorityDepositsAccepted);
    }

    function test_doClearing_testDepositsAcceptOnlyExcess_shouldOnlyAcceptSeniors() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 0;

        input.balance.owed = 1_000_000 * 1e6;
        input.balance.excess = 0;

        // new accepted deposit should be 100_000 * 1e6 to seniors as we only accept the excess amount
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 100_000 * 1e6 + 100_000 * 1e6 = 100_000 * 1e6

        // total deposit
        input.pendingDeposits.totalDepositAmount = 105_000 * 1e6;
        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 55_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 30_000 * 1e6; // mezzanine
        input.pendingDeposits.trancheDepositsAmounts[2] = 20_000 * 1e6; // senior
        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 25_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 15_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // mezzanine priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 10_000 * 1e6; // mezzanine priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 5_000 * 1e6; // mezzanine priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][0] = 10_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][1] = 5_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][2] = 5_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT in the order as the deposits are accepted
        // junior deposits to junior
        assertEq(tranchePriorityDepositsAccepted[0][2][0], 0); // junior priority 2 to junior
        assertEq(tranchePriorityDepositsAccepted[0][1][0], 0); // junior priority 1 to junior
        assertEq(tranchePriorityDepositsAccepted[0][0][0], 0); // junior priority 0 to junior

        // deposits to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][2][1], 0); // mezzanine priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][2][1], 0); // junior priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][1][1], 0); // mezzanine priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][1][1], 0); // junior priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][0][1], 0); // mezzanine priority 0 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][0][1], 0); // junior priority 0 to mezzanine

        // deposits to senior
        assertEq(tranchePriorityDepositsAccepted[2][2][2], input.pendingDeposits.tranchePriorityDepositsAmounts[2][2]); // senior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[1][2][2], input.pendingDeposits.tranchePriorityDepositsAmounts[1][2]); // mezzanine priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[0][2][2], input.pendingDeposits.tranchePriorityDepositsAmounts[0][2]); // junior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[2][1][2], input.pendingDeposits.tranchePriorityDepositsAmounts[2][1]); // senior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[1][1][2], input.pendingDeposits.tranchePriorityDepositsAmounts[1][1]); // mezzanine priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[0][1][2], input.pendingDeposits.tranchePriorityDepositsAmounts[0][1]); // junior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[2][0][2], input.pendingDeposits.tranchePriorityDepositsAmounts[2][0]); // senior priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[1][0][2], input.pendingDeposits.tranchePriorityDepositsAmounts[1][0]); // mezzanine priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[0][0][2], 20_000 * 1e6); // junior priority 0 to senior

        // ASSERT values that should always be 0
        _assertDepositAcceptedAlwaysZeroValues(tranchePriorityDepositsAccepted);
    }

    function test_doClearing_zeroAcceptedAsExcessIsEnough() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 300_000 * 1e6;

        // new accepted deposit should be 0
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 300_000 * 1e6 + 100_000 * 1e6 = -100_000 * 1e6 (value is negative, so 0)

        // total deposit
        input.pendingDeposits.totalDepositAmount = 105_000 * 1e6;
        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 55_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 30_000 * 1e6; // mezzanine
        input.pendingDeposits.trancheDepositsAmounts[2] = 20_000 * 1e6; // senior
        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 25_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 15_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // mezzanine priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 10_000 * 1e6; // mezzanine priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 5_000 * 1e6; // mezzanine priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][0] = 10_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][1] = 5_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][2] = 5_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT all values are 0
        for (uint256 i; i < tranchePriorityDepositsAccepted.length; ++i) {
            for (uint256 j; j < tranchePriorityDepositsAccepted[i].length; ++j) {
                for (uint256 k; k < tranchePriorityDepositsAccepted[i][j].length; ++k) {
                    assertEq(tranchePriorityDepositsAccepted[i][j][k], 0);
                }
            }
        }
    }

    function test_doClearing_testTwoTranches() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        input.config.trancheDesiredRatios = new uint256[](2);
        input.config.trancheDesiredRatios[0] = 25_00;
        input.config.trancheDesiredRatios[1] = 75_00;

        // new accepted deposit should be 100_000 * 1e6
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 100_000 * 1e6 + 100_000 * 1e6 = 100_000 * 1e6

        input.pendingDeposits.trancheDepositsAmounts = new uint256[](2);
        input.pendingDeposits.tranchePriorityDepositsAmounts = new uint256[][](3);
        input.pendingDeposits.tranchePriorityDepositsAmounts[0] = new uint256[](3);
        input.pendingDeposits.tranchePriorityDepositsAmounts[1] = new uint256[](3);

        // total deposit
        input.pendingDeposits.totalDepositAmount = 105_000 * 1e6;

        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 55_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 50_000 * 1e6; // senior

        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 25_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 15_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 20_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 15_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT in the order as the deposits are accepted
        // junior deposits to junior
        assertEq(tranchePriorityDepositsAccepted[0][2][0], 15_000 * 1e6); // junior priority 2 to junior
        assertEq(tranchePriorityDepositsAccepted[0][1][0], 10_000 * 1e6); // junior priority 1 to junior
        assertEq(tranchePriorityDepositsAccepted[0][0][0], 0); // junior priority 0 to junior

        // deposits to senior
        assertEq(tranchePriorityDepositsAccepted[1][2][1], 15_000 * 1e6); // senior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[0][2][1], 0); // junior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[1][1][1], 20_000 * 1e6); // senior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[0][1][1], 5_000 * 1e6); // junior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[1][0][1], 15_000 * 1e6); // senior priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[0][0][1], 20_000 * 1e6); // junior priority 0 to senior

        // ASSERT values that should always be 0
        _assertDepositAcceptedAlwaysZeroValues(tranchePriorityDepositsAccepted);
    }

    function test_doClearing_testOneTranche() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        input.config.trancheDesiredRatios = new uint256[](1);
        input.config.trancheDesiredRatios[0] = 100_00;

        // new accepted deposit should be 100_000 * 1e6
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 100_000 * 1e6 + 100_000 * 1e6 = 100_000 * 1e6

        input.pendingDeposits.trancheDepositsAmounts = new uint256[](1);
        input.pendingDeposits.tranchePriorityDepositsAmounts = new uint256[][](1);
        input.pendingDeposits.tranchePriorityDepositsAmounts[0] = new uint256[](3);

        // total deposit
        input.pendingDeposits.totalDepositAmount = 105_000 * 1e6;

        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 105_000 * 1e6; // senior

        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 55_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 35_000 * 1e6; // senior priority 2

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted,) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT in the order as the deposits are accepted
        // deposits to senior
        assertEq(tranchePriorityDepositsAccepted[0][2][0], 35_000 * 1e6); // senior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[0][1][0], 15_000 * 1e6); // senior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[0][0][0], 50_000 * 1e6); // senior priority 0 to senior

        // ASSERT values that should always be 0
        _assertDepositAcceptedAlwaysZeroValues(tranchePriorityDepositsAccepted);
    }

    function test_doClearing_testFullWithdrawals() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.minExcessPercentage = 0;

        input.balance.owed = 1_000_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        input.pendingWithdrawals.totalWithdrawalsAmount = 100_000 * 1e6;
        input.pendingWithdrawals.priorityWithdrawalAmounts[0] = 10_000 * 1e6; // priority 0 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[1] = 20_000 * 1e6; // priority 1 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[2] = 30_000 * 1e6; // priority 2 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[3] = 40_000 * 1e6; // priority 3 withdrawal

        // ACT
        (, uint256[] memory acceptedPriorityWithdrawalAmounts) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT
        for (uint256 i; i < acceptedPriorityWithdrawalAmounts.length; ++i) {
            assertEq(acceptedPriorityWithdrawalAmounts[i], input.pendingWithdrawals.priorityWithdrawalAmounts[i]);
        }
    }

    function test_doClearing_testFullPartialWithdrawals() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.minExcessPercentage = 0;

        input.balance.owed = 1_000_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        input.pendingWithdrawals.totalWithdrawalsAmount = 115_000 * 1e6;
        input.pendingWithdrawals.priorityWithdrawalAmounts[0] = 10_000 * 1e6; // priority 0 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[1] = 20_000 * 1e6; // priority 1 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[2] = 30_000 * 1e6; // priority 2 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[3] = 55_000 * 1e6; // priority 3 withdrawal

        // ACT
        (, uint256[] memory acceptedPriorityWithdrawalAmounts) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT
        assertEq(acceptedPriorityWithdrawalAmounts[0], 0);
        assertEq(acceptedPriorityWithdrawalAmounts[1], 15_000 * 1e6);
        assertEq(acceptedPriorityWithdrawalAmounts[2], input.pendingWithdrawals.priorityWithdrawalAmounts[2]);
        assertEq(acceptedPriorityWithdrawalAmounts[3], input.pendingWithdrawals.priorityWithdrawalAmounts[3]);
    }

    function test_doClearing_moreAvailableWithdrawalsThanRequested() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.minExcessPercentage = 0;

        input.balance.owed = 1_000_000 * 1e6;
        input.balance.excess = 200_000 * 1e6;

        input.pendingWithdrawals.totalWithdrawalsAmount = 115_000 * 1e6;
        input.pendingWithdrawals.priorityWithdrawalAmounts[0] = 10_000 * 1e6; // priority 0 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[1] = 20_000 * 1e6; // priority 1 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[2] = 30_000 * 1e6; // priority 2 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[3] = 55_000 * 1e6; // priority 3 withdrawal

        // ACT
        (, uint256[] memory acceptedPriorityWithdrawalAmounts) = clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT
        for (uint256 i; i < acceptedPriorityWithdrawalAmounts.length; ++i) {
            assertEq(acceptedPriorityWithdrawalAmounts[i], input.pendingWithdrawals.priorityWithdrawalAmounts[i]);
        }
    }

    function test_doClearing_testDepositsAndWithdrawals() public {
        // ARRANGE
        ClearingInput memory input = _getDefaultClearingInput();

        input.config.borrowAmount = 100_000 * 1e6;

        input.balance.owed = 900_000 * 1e6;
        input.balance.excess = 100_000 * 1e6;

        // new maximum accepted deposit should be 100_000 * 1e6 + withdrawal amount
        // ((balance.owed + input.config.borrowAmount) * config.maxExcessPercentage) - input.balance.excess + input.config.borrowAmount
        // ((900_000 * 1e6 + 100_000 * 1e6) * 10%) - 100_000 * 1e6 + 100_000 * 1e6 = 100_000 * 1e6

        // total deposit
        input.pendingDeposits.totalDepositAmount = 110_000 * 1e6;
        // deposit per tranche
        input.pendingDeposits.trancheDepositsAmounts[0] = 60_000 * 1e6; // junior
        input.pendingDeposits.trancheDepositsAmounts[1] = 30_000 * 1e6; // mezzanine
        input.pendingDeposits.trancheDepositsAmounts[2] = 20_000 * 1e6; // senior
        // deposit per tranche and priority
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][0] = 30_000 * 1e6; // junior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][1] = 15_000 * 1e6; // junior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[0][2] = 15_000 * 1e6; // junior priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][0] = 15_000 * 1e6; // mezzanine priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][1] = 10_000 * 1e6; // mezzanine priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[1][2] = 5_000 * 1e6; // mezzanine priority 2
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][0] = 10_000 * 1e6; // senior priority 0
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][1] = 5_000 * 1e6; // senior priority 1
        input.pendingDeposits.tranchePriorityDepositsAmounts[2][2] = 5_000 * 1e6; // senior priority 2

        // accepted withdrawal amount should be 60_000 * 1e6
        input.pendingWithdrawals.totalWithdrawalsAmount = 100_000 * 1e6;
        input.pendingWithdrawals.priorityWithdrawalAmounts[0] = 10_000 * 1e6; // priority 0 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[1] = 20_000 * 1e6; // priority 1 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[2] = 30_000 * 1e6; // priority 2 withdrawal
        input.pendingWithdrawals.priorityWithdrawalAmounts[3] = 40_000 * 1e6; // priority 3 withdrawal

        // ACT
        (uint256[][][] memory tranchePriorityDepositsAccepted, uint256[] memory acceptedPriorityWithdrawalAmounts) =
            clearingCalculation.calculateAcceptedRequests(input);

        // ASSERT in the order as the deposits are accepted
        // junior deposits to junior
        // accepted 22_000 * 1e6
        assertEq(tranchePriorityDepositsAccepted[0][2][0], 15_000 * 1e6, "junior priority 2 to junior"); // junior priority 2 to junior
        assertEq(tranchePriorityDepositsAccepted[0][1][0], 7_000 * 1e6, "junior priority 1 to junior"); // junior priority 1 to junior
        assertEq(tranchePriorityDepositsAccepted[0][0][0], 0, "junior priority 0 to junior"); // junior priority 0 to junior

        // deposits to mezzanine
        // accepted 33_000 * 1e6
        assertEq(tranchePriorityDepositsAccepted[1][2][1], 5_000 * 1e6, "mezzanine priority 2 to mezzanine"); // mezzanine priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][2][1], 0, "junior priority 2 to mezzanine"); // junior priority 2 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][1][1], 10_000 * 1e6, "mezzanine priority 1 to mezzanine"); // mezzanine priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][1][1], 8_000 * 1e6, "junior priority 1 to mezzanine"); // junior priority 1 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[1][0][1], 10_000 * 1e6, "mezzanine priority 0 to mezzanine"); // mezzanine priority 0 to mezzanine
        assertEq(tranchePriorityDepositsAccepted[0][0][1], 0, "junior priority 0 to mezzanine"); // junior priority 0 to mezzanine

        // deposits to senior
        // accepted 55_000 * 1e6
        assertEq(tranchePriorityDepositsAccepted[2][2][2], 5_000 * 1e6, "senior priority 2 to senior"); // senior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[1][2][2], 0, "mezzanine priority 2 to senior"); // mezzanine priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[0][2][2], 0, "junior priority 2 to senior"); // junior priority 2 to senior
        assertEq(tranchePriorityDepositsAccepted[2][1][2], 5_000 * 1e6, "senior priority 1 to senior"); // senior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[1][1][2], 0, "mezzanine priority 1 to senior"); // mezzanine priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[0][1][2], 0, "junior priority 1 to senior"); // junior priority 1 to senior
        assertEq(tranchePriorityDepositsAccepted[2][0][2], 10_000 * 1e6, "senior priority 0 to senior"); // senior priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[1][0][2], 5_000 * 1e6, "mezzanine priority 0 to senior"); // mezzanine priority 0 to senior
        assertEq(tranchePriorityDepositsAccepted[0][0][2], 30_000 * 1e6, "junior priority 0 to senior"); // junior priority 0 to senior

        // ASSERT deposit values that should always be 0
        _assertDepositAcceptedAlwaysZeroValues(tranchePriorityDepositsAccepted);

        // ASSERT withdrawal values
        assertEq(acceptedPriorityWithdrawalAmounts[0], 0);
        assertEq(acceptedPriorityWithdrawalAmounts[1], 0);
        assertEq(acceptedPriorityWithdrawalAmounts[2], 20_000 * 1e6);
        assertEq(acceptedPriorityWithdrawalAmounts[3], input.pendingWithdrawals.priorityWithdrawalAmounts[3]);
    }

    function _getDefaultClearingInput() private pure returns (ClearingInput memory input) {
        ClearingConfiguration memory config;
        config.borrowAmount = 0;
        config.trancheDesiredRatios = new uint256[](3);
        config.trancheDesiredRatios[0] = 20_00;
        config.trancheDesiredRatios[1] = 30_00;
        config.trancheDesiredRatios[2] = 50_00;
        config.maxExcessPercentage = 10_00;
        config.minExcessPercentage = 5_00;

        LendingPoolBalance memory balance;
        balance.owed = 0;
        balance.excess = 0;

        PendingDeposits memory pendingDeposits;
        pendingDeposits.trancheDepositsAmounts = new uint256[](3);
        pendingDeposits.tranchePriorityDepositsAmounts = new uint256[][](3);
        pendingDeposits.tranchePriorityDepositsAmounts[0] = new uint256[](3);
        pendingDeposits.tranchePriorityDepositsAmounts[1] = new uint256[](3);
        pendingDeposits.tranchePriorityDepositsAmounts[2] = new uint256[](3);

        PendingWithdrawals memory pendingWithdrawals;
        pendingWithdrawals.priorityWithdrawalAmounts = new uint256[](4);

        input.config = config;
        input.balance = balance;
        input.pendingDeposits = pendingDeposits;
        input.pendingWithdrawals = pendingWithdrawals;
    }

    function _assertDepositAcceptedAlwaysZeroValues(uint256[][][] memory tranchePriorityDepositsAccepted) private {
        for (uint256 i; i < tranchePriorityDepositsAccepted.length; ++i) {
            for (uint256 j; j < tranchePriorityDepositsAccepted[i].length; ++j) {
                for (uint256 k; k < tranchePriorityDepositsAccepted[i][j].length; ++k) {
                    if (i > k) {
                        assertEq(tranchePriorityDepositsAccepted[i][j][k], 0);
                    }
                }
            }
        }
    }
}
