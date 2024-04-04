// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../../src/token/KSU.sol";
import {MockUSDC} from "../../shared/MockUSDC.sol";
import "../_utils/LockingTestUtils.sol";

contract LockingWorkflowTest is LockingTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();

        TransparentUpgradeableProxy ksuLockBonusProxy =
            new TransparentUpgradeableProxy(address(new KSULockBonus()), address(proxyAdmin), "");
        _KSULockBonus = KSULockBonus(address(ksuLockBonusProxy));
        _KSULockBonus.initialize(address(_KSULocking), _ksu);
        vm.prank(admin);
        _KSULocking.setKSULockBonus(address(_KSULockBonus));
    }

    /*
     *  ### Test Case 1
     *
     *  Description
     *  Four users in two years period lock KSU, claim their rewards and unlock.
     *
     *  Steps:
     *  -   Admin adds 300 KSU to Lock Bonus Contract
     *  -   Alice locks 100 KSU for 30d
     *  -   Bob locks 400 KSU for 180d
     *  -   A reward of 500 USC is emitted to Lock Contract
     *  -   30d pass
     *  -   Carol locks 500 KSU for 720d
     *  -   Alice collect her rewards - USDC
     *  -   Alice unlocks 50 KSU of her locked amount - KSU
     *  -   A reward of 200 USC is emitted to Lock Contract
     *  -   David locks 500 KSU for 360d
     *  -   Alice locks 800 KSU for 180d
     *  -   A reward of 600 USC is emitted to Lock Contract
     *  -   180d pass
     *  -   Bob collect his rewards - USDC
     *  -   Bob unlocks 200 KSU of his locked amount - KSU
     *  -   A reward of 400 USC is emitted to Lock Contract
     *  -   360d pass
     *  -   David collect his rewards - USDC
     *  -   David unlocks all of his locked amount - KSU
     *  -   360d pass
     *  -   Carol collects her rewards - USDC
     *  -   Everyone unlocks
     *  -   Everyone claims
     */
    function testCase1() public {
        // Admin adds 300 KSU to Lock Bonus Contract
        _addBonusKSU(300 ether);
        // Alice locks 100 KSU for 30d
        _lock(alice, 100 ether, lockPeriod30);
        assertApproxEqAbs(_ksu.balanceOf(address(alice)), 0, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(alice), 100 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(alice)), 5 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 5 ether, 0);
        // Bob locks 400 KSU for 180d
        _lock(bob, 400 ether, lockPeriod180);
        assertApproxEqAbs(_ksu.balanceOf(address(bob)), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(bob), 440 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(bob)), 110 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 115 ether, 0);
        // A reward of 500 USC is emitted to Lock Contract
        _emitFees(500 * 1e6);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 500 * 1e6, 0);
        // 30d pass
        skip(lockPeriod30);
        // Carol locks 500 KSU for 720d
        _lock(carol, 500 ether, lockPeriod720);
        assertApproxEqAbs(_ksu.balanceOf(address(carol)), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(carol), 760 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(carol)), 760 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 875 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1300 ether, 0);
        // Alice collects her rewards - USDC
        _claimFees(alice);
        assertApproxEqAbs(mockUsdc.balanceOf(address(alice)), 21739130, 0);
        // Bob collects hid rewards - USDC
        _claimFees(bob);
        uint256 bobRewardEmit1 = 478260869;
        assertApproxEqAbs(mockUsdc.balanceOf(address(bob)), bobRewardEmit1, 0);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 0, 1); // 0 vs 1
        // Alice unlocks 50 KSU of her locked amount - KSU
        _unlock(alice, 50 ether, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(alice), 50 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(alice)), 2.5 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(alice)), 50 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1250 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 872.5 ether, 0);
        // A reward of 200 USC is emitted to Lock Contract
        _emitFees(200 * 1e6);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 200 * 1e6, 1); // 200.000001
        // David locks 500 KSU for 360d
        _lock(david, 400 ether, lockPeriod360);
        assertApproxEqAbs(_ksu.balanceOf(address(david)), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(david), 400 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(david)), 200 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1650 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 1072.5 ether, 0);
        // Alice locks 800 KSU for 180d
        _lock(alice, 800 ether, lockPeriod180);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(alice), 850 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(alice)), 202.5 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 2450 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 1272.5 ether, 0);
        // A reward of 600 USC is emitted to Lock Contract
        _emitFees(600 * 1e6);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 800 * 1e6, 1); // 800.000001
        // 180d pass
        skip(lockPeriod180);
        // Bob collect his rewards // USDC
        _claimFees(bob);
        uint256 bobRewardEmit2 = 25214899;
        uint256 bobRewardEmit3 = 51866404;
        assertApproxEqAbs(mockUsdc.balanceOf(address(bob)), bobRewardEmit1 + bobRewardEmit2 + bobRewardEmit3, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 800 * 1e6 - bobRewardEmit2 - bobRewardEmit3, 1);
        // Bob unlocks 200 of his locked amount // KSU
        _unlock(bob, 200 ether, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(bob), 240 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(bob)), 60 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(bob)), 200 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 2250 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 1222.5 ether, 0);
        // A reward of 400 USC is emitted to Lock Contract
        _emitFees(400 * 1e6);
        uint256 expectedEmit4Balance = 800 * 1e6 + 400 * 1e6 - bobRewardEmit2 - bobRewardEmit3;
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), expectedEmit4Balance, 1);
        // 360d pass
        skip(lockPeriod360);
        // David collect his rewards // USDC
        _claimFees(david);
        assertApproxEqAbs(mockUsdc.balanceOf(address(david)), 159742226, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), expectedEmit4Balance - 159742226, 1);
        // David unlocks all of his locked amount // KSU
        _unlockAll(david, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(david), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(david)), 0 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(david)), 400 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1850 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 1022.5 ether, 0);
        // 360d pass
        skip(lockPeriod360);
        // Carol collects her rewards // USDC
        _claimFees(carol);
        assertApproxEqAbs(mockUsdc.balanceOf(address(carol)), 781232496, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), expectedEmit4Balance - 159742226 - 781232496, 1);
        // Everyone unlocks
        _unlockAll(alice, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(alice), 800 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(alice)), 200 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(alice)), 50 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1800 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 1020 ether, 0);
        _unlockAll(alice, 1);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(alice), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(alice)), 0 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(alice)), 850 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1000 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 820 ether, 0);
        _unlockAll(bob, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(bob), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(bob)), 0 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(bob)), 440 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 760 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 760 ether, 0);
        _unlockAll(carol, 0);
        assertApproxEqAbs(_KSULocking.userTotalDeposits(carol), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.balanceOf(address(carol)), 0 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(carol)), 760 ether, 0);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 0 ether, 0);
        assertApproxEqAbs(_KSULocking.totalSupply(), 0 ether, 0);
        // Everyone claims
        _claimFees(alice);
        assertApproxEqAbs(mockUsdc.balanceOf(address(alice)), 184051201, 1);
        _claimFees(bob);
        assertApproxEqAbs(mockUsdc.balanceOf(address(bob)), 574974075, 1);
        _claimFees(carol);
        assertApproxEqAbs(mockUsdc.balanceOf(address(carol)), 781232496, 1);
        _claimFees(david);
        assertApproxEqAbs(mockUsdc.balanceOf(address(david)), 159742226, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 0, 2);
    }

    function _logBalanceOf(string memory msg_, IERC20 token, address user) internal {
        emit log_named_decimal_uint(msg_, token.balanceOf(user), IERC20Metadata(address(token)).decimals());
    }

    function _logBalanceOf(string memory msg_, address token, address user) internal {
        IERC20 t = IERC20(token);
        _logBalanceOf(msg_, t, user);
    }

    function _logBalanceOf(address token, address user) internal {
        _logBalanceOf("", token, user);
    }
}
