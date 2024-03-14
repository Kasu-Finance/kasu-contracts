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

        uint256 dNftId_alice = _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 100 * 10 ** 6);
        uint256 dNftId_bob = _requestDeposit(bob, lpd.lendingPool, lpd.tranches[1], 250 * 10 ** 6);
        uint256 dNftId_carol = _requestDeposit(carol, lpd.lendingPool, lpd.tranches[2], 50 * 10 ** 6);

        _acceptDepositRequest(lpd.lendingPool, dNftId_alice, 40 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_bob, 200 * 10 ** 6);
        _acceptDepositRequest(lpd.lendingPool, dNftId_carol, 50 * 10 ** 6);

        uint256 wNftId_alice = _requestWithdrawal(alice, lpd.lendingPool, lpd.tranches[0], 40 * 10 ** 18);
        uint256 wNftId1_bob = _requestWithdrawal(bob, lpd.lendingPool, lpd.tranches[1], 200 * 10 ** 18);

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        _lock(alice, 200 ether, lockPeriod30);

        // ### ACT ###
        IPendingPool pendingPool = IPendingPool(lpd.pendingPool);
        pendingPool.calculatePendingRequestsPriority(10, currentEpoch);

        // ### ASSERT ###
        PendingDeposits memory pendingDeposits = pendingPool.getPendingDeposits(currentEpoch);
        assertEq(pendingDeposits.totalDepositAmount, 110 * 10 ** 6);
        assertEq(pendingDeposits.trancheDepositsAmounts.length, 3);
        assertEq(pendingDeposits.trancheDepositsAmounts[0], 60 * 10 ** 6);
        assertEq(pendingDeposits.trancheDepositsAmounts[1], 50 * 10 ** 6);
        assertEq(pendingDeposits.trancheDepositsAmounts[2], 0 * 10 ** 6);

        //TODO: test loyalty levels

        PendingWithdrawals memory pendingWithdrawals = pendingPool.getPendingWithdrawals(currentEpoch);
        assertEq(pendingWithdrawals.totalWithdrawalsAmount, 240 * 10 ** 6);

        //TODO: access control to functions that need to be stopped
    }
}
