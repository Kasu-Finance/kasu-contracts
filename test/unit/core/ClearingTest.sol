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
        uint256 dNftId_david = _requestDeposit(david, lpd.lendingPool, lpd.tranches[0], 10 * 1e6);
        _requestDeposit(userFive, lpd.lendingPool, lpd.tranches[0], 500 * 1e6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 1e6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 200 * 1e6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_carol, 50 * 1e6);

        _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[0], 200 * 10 ** 18);

        // tranche 2
        _requestDeposit(userSix, lpd.lendingPool, lpd.tranches[1], 150 * 1e6);
        _requestDeposit(userSeven, lpd.lendingPool, lpd.tranches[1], 60 * 1e6);

        // tranche 3
        uint256 dNftId_userEight = _requestDeposit(userEight, lpd.lendingPool, lpd.tranches[2], 80 * 1e6);
        _requestDeposit(userNine, lpd.lendingPool, lpd.tranches[2], 20 * 1e6);
        _requestDeposit(userTen, lpd.lendingPool, lpd.tranches[2], 180 * 1e6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_userEight, 10 * 1e6);

        ForceWithdrawalInput[] memory input1 = new ForceWithdrawalInput[](1);
        input1[0] = ForceWithdrawalInput(lpd.tranches[2], userEight, 10 * 10 ** 18);
        _batchForceWithdrawals(lendingPoolManagerAccount, lpd.lendingPool, input1)[0];

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        // user locking
        // loyalty levels: 0-1%: 0, 1%-3%:1, 3%+: 2
        _lock(bob, 3 ether, lockPeriod180); // 0,25 * 3e18 * 2e18 / 1e18 / 1e12 = 1.5 usdc / 250 usdc -> 0.6%
        _lock(userFive, 8 ether, lockPeriod360); // 0,5 * 8e18 * 2e18 / 1e18 / 1e12 = 8 usdc / 500 usdc- > 1.6%
        _lock(alice, 25 ether, lockPeriod30); // 0,05 * 15e18 * 2e18 / 1e18 / 1e12 = 2.5 usdc / 100 usdc = 2.5%
        _lock(carol, 5 ether, lockPeriod360); // 0,5 * 5e18 * 2e18 / 1e18 / 1e12 = 5 usdc / 50 usdc- > 10%
        _lock(david, 5 ether, lockPeriod360); // 0,5 * 5e18 * 2e18 / 1e18 / 1e12 = 5 usdc / 50 usdc- > 50%

        skip(6 days);

        userManager.batchCalculateUserLoyaltyLevels(20);

        // ### ACT ###
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        pendingPool.calculatePendingRequestsPriority(20, currentEpoch);

        // ### ASSERT ###
        PendingDeposits memory pendingDeposits = pendingPool.getPendingDeposits(currentEpoch);
        assertEq(pendingDeposits.totalDepositAmount, 1100 * 1e6);
        assertEq(pendingDeposits.trancheDepositsAmounts.length, 3);
        assertEq(pendingDeposits.trancheDepositsAmounts[0], 620 * 1e6);
        assertEq(pendingDeposits.trancheDepositsAmounts[1], 210 * 1e6);
        assertEq(pendingDeposits.trancheDepositsAmounts[2], 270 * 1e6);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][0], 50 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][1], 560 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[0][2], 10 * 1e6);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][0], 210 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][1], 0);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[1][2], 0);

        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][0], 270 * 1e6);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][1], 0);
        assertEq(pendingDeposits.tranchePriorityDepositsAmounts[2][2], 0);

        PendingWithdrawals memory pendingWithdrawals = pendingPool.getPendingWithdrawals(currentEpoch);
        assertEq(pendingWithdrawals.totalWithdrawalsAmount, 250 * 1e6);

        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[0], 200 * 1e6);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[1], 40 * 1e6);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[2], 0);
        assertEq(pendingWithdrawals.priorityWithdrawalAmounts[3], 10 * 1e6);
    }
}
