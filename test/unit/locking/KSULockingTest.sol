// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../_utils/LockingTestUtils.sol";
import "../../shared/SigUtilsERC20.sol";
import "../../../src/locking/KSULockBonus.sol";
import "../../../src/locking/interfaces/IKSULocking.sol";
import "../../../src/core/Constants.sol";
import "../../../src/shared/access/Roles.sol";

contract KSULockingTest is LockingTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
    }

    function test_addLockPeriod_WhenNotAdmin_ShouldRevert() public {
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier30);
    }

    function testAddLockPeriod_WhenExists_ShouldRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IKSULocking.LockPeriodAlreadyExists.selector, lockPeriod30));
        vm.prank(admin);
        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier30);
    }

    function test_emitFees() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;

        // ACT / ASSERT
        vm.startPrank(admin);
        mockUsdc.approve(address(_KSULocking), rewardAmount);
        vm.expectEmit(true, false, false, true, address(_KSULocking));
        emit IKSULocking.FeesEmitted(address(admin), rewardAmount);
        deal(address(mockUsdc), admin, rewardAmount, true);
        _KSULocking.emitFees(rewardAmount);
        vm.stopPrank();

        // ASSERT
        assertEq(mockUsdc.balanceOf(address(_KSULocking)), rewardAmount);
    }

    function test_lock() public {
        // ARRANGE
        uint256 aliceLockAmount = 100 ether;

        // ACT / ASSERT
        uint256 aliceExpectedRksuAmount = aliceLockAmount * lockMultiplier30 / FULL_PERCENT;
        startHoax(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, true, true, address(_KSULocking));
        emit IKSULocking.UserLocked(address(alice), 0, lockPeriod30, aliceLockAmount, 0 ether, aliceExpectedRksuAmount);
        deal(address(_ksu), alice, aliceLockAmount, true);
        _KSULocking.lock(aliceLockAmount, lockPeriod30);

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), aliceLockAmount);
        assertEq(_KSULocking.balanceOf(alice), aliceExpectedRksuAmount);
    }

    function test_lockWithPermit() public {
        // ARRANGE
        SigUtilsERC20 sigUtilsERC20 = new SigUtilsERC20(_ksu.DOMAIN_SEPARATOR());

        uint256 lockAmount = 100 ether;
        uint256 deadline = 1 days;
        uint256 userPrivateKey = 0xA11CE;
        address user = vm.addr(userPrivateKey);
        deal(address(_ksu), user, 1000 ether, true);

        // ACT
        SigUtilsERC20.Permit memory permit = SigUtilsERC20.Permit({
            owner: user,
            spender: address(_KSULocking),
            value: lockAmount,
            nonce: _ksu.nonces(user),
            deadline: deadline
        });

        bytes32 digest = sigUtilsERC20.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        hoax(user);
        _KSULocking.lockWithPermit(
            lockAmount,
            lockPeriod30,
            IKSULocking.ERC20PermitPayload({value: lockAmount, deadline: deadline, v: v, r: r, s: s})
        );

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), lockAmount);
        assertEq(_KSULocking.balanceOf(user), lockAmount * lockMultiplier30 / FULL_PERCENT);
    }

    function test_lockWithBonusKSU() public {
        // ARRANGE
        _KSULockBonus = new KSULockBonus();
        _KSULockBonus.initialize(address(_KSULocking), _ksu);
        vm.prank(admin);
        _KSULocking.setKSULockBonus(address(_KSULockBonus));
        _addBonusKSU(1000 ether);

        // ACT / ASSER
        uint256 aliceLockAmount = 100 ether;
        uint256 expectedAliceBaseKSULockAmount = 100 ether;
        uint256 expectedAliceBonusKSULockAmount = 10 ether;

        uint256 aliceExpectedLockedRKSUAmount =
            (expectedAliceBaseKSULockAmount + expectedAliceBonusKSULockAmount) * lockMultiplier180 / FULL_PERCENT;

        vm.startPrank(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, true, true, address(_KSULocking));
        emit IKSULocking.UserLocked(
            address(alice),
            0,
            lockPeriod180,
            expectedAliceBaseKSULockAmount,
            expectedAliceBonusKSULockAmount,
            aliceExpectedLockedRKSUAmount
        );
        deal(address(_ksu), alice, aliceLockAmount, true);
        _KSULocking.lock(aliceLockAmount, lockPeriod180);
        vm.stopPrank();

        uint256 bobLockAmount = 200 ether;
        uint256 expectedBobBaseKSULockAmount = 200 ether;
        uint256 expectedBobBonusKSULockAmount = 50 ether;

        uint256 bobExpectedLockedRKSUAmount =
            (expectedBobBaseKSULockAmount + expectedBobBonusKSULockAmount) * lockMultiplier360 / FULL_PERCENT;
        vm.startPrank(bob);
        _ksu.approve(address(_KSULocking), bobLockAmount);
        vm.expectEmit(true, true, true, true, address(_KSULocking));
        emit IKSULocking.UserLocked(
            address(bob),
            0,
            lockPeriod360,
            expectedBobBaseKSULockAmount,
            expectedBobBonusKSULockAmount,
            bobExpectedLockedRKSUAmount
        );
        deal(address(_ksu), bob, bobLockAmount, true);
        _KSULocking.lock(bobLockAmount, lockPeriod360);
        vm.stopPrank();

        // ASSERT

        assertEq(_KSULocking.balanceOf(alice), aliceExpectedLockedRKSUAmount);

        assertEq(
            _ksu.balanceOf(address(_KSULocking)),
            expectedBobBaseKSULockAmount + expectedBobBonusKSULockAmount + expectedAliceBaseKSULockAmount
                + expectedAliceBonusKSULockAmount
        );
        assertEq(_KSULocking.balanceOf(bob), bobExpectedLockedRKSUAmount);
    }

    function test_lockRewards() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;
        uint256 aliceLockAmount = 200 ether;

        _lock(alice, aliceLockAmount, lockPeriod30);
        _emitFees(rewardAmount);

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), aliceLockAmount);
        assertEq(mockUsdc.balanceOf(address(_KSULocking)), rewardAmount);

        // ACT
        vm.startPrank(alice);
        vm.expectEmit();
        emit IKSULocking.FeesClaimed(address(alice), rewardAmount);
        _KSULocking.claimFees();
        vm.stopPrank();

        // ASSERT
        assertApproxEqAbs(mockUsdc.balanceOf(address(_KSULocking)), 0, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(alice)), rewardAmount, 1);
    }

    function test_lockRewardsForTwoUsersOneDeposit() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;
        uint256 aliceLockAmount = 100 ether;
        uint256 bobLockAmount = 300 ether;

        _lock(alice, aliceLockAmount, lockPeriod30);
        _lock(bob, bobLockAmount, lockPeriod30);
        _emitFees(rewardAmount);

        // ACT
        _claimFees(alice);
        _claimFees(bob);

        // ASSERT
        assertApproxEqAbs(mockUsdc.balanceOf(address(alice)), 25 * 1e6, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(bob)), 75 * 1e6, 1);
    }

    function test_lockRewardsForTwoUsersMultipleDepositsAndRewards() public {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit1 = 100 ether;
        uint256 bobLockAmountDeposit1 = 300 ether;

        _lock(alice, aliceLockAmountDeposit1, lockPeriod30);
        _lock(bob, bobLockAmountDeposit1, lockPeriod30);
        _emitFees(reward1Amount);

        uint256 reward2Amount = 50 * 1e6;
        uint256 aliceLockAmountDeposit2 = 200 ether;
        uint256 bobLockAmountDeposit2 = 200 ether;

        _lock(alice, aliceLockAmountDeposit2, lockPeriod30);
        _lock(bob, bobLockAmountDeposit2, lockPeriod30);
        _emitFees(reward2Amount);

        // ACT
        vm.prank(alice);
        _KSULocking.claimFees();
        vm.prank(bob);
        _KSULocking.claimFees();

        // ASSERT
        assertApproxEqAbs(mockUsdc.balanceOf(address(alice)), 25 * 1e6 + 1875 * 1e4, 1);
        assertApproxEqAbs(mockUsdc.balanceOf(address(bob)), 75 * 1e6 + 3125 * 1e4, 1);
    }

    function test_unlock() public {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit1 = 100 ether;

        _lock(alice, aliceLockAmountDeposit1, lockPeriod30);
        _emitFees(reward1Amount);

        skip(lockPeriod30);

        // ACT / ASSERT
        uint256 aliceUnLockAmount = 80 ether;
        uint256 aliceExpectedBurnedRksu = 4 ether;

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit IKSULocking.UserUnlocked(address(alice), 0, aliceUnLockAmount, aliceExpectedBurnedRksu);
        _KSULocking.unlock(aliceUnLockAmount, 0);
        vm.stopPrank();
    }

    function test_unlockWhenNotExpired_ShouldRevert() public {
        // ARRANGE
        uint256 aliceLockAmountDeposit = 100 ether;

        uint256 lockId = _lock(alice, aliceLockAmountDeposit, lockPeriod30);

        // ACT / ASSERT
        uint256 aliceUnLockAmount = 80 ether;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IKSULocking.DepositLocked.selector, lockId));
        _KSULocking.unlock(aliceUnLockAmount, 0);
    }

    function test_unlockForTwoUsers() public {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit = 100 ether;
        uint256 bobLockAmountDeposit = 300 ether;

        _lock(alice, aliceLockAmountDeposit, lockPeriod30);
        _lock(bob, bobLockAmountDeposit, lockPeriod30);
        _emitFees(reward1Amount);

        skip(lockPeriod30);

        // ACT
        _unlock(alice, 80 ether, 0);
        _unlock(bob, 220 ether, 0);

        // ASSERT
        assertApproxEqAbs(_KSULocking.balanceOf(alice), 20 ether * lockMultiplier30 / FULL_PERCENT, 1);
        assertApproxEqAbs(_KSULocking.balanceOf(bob), 80 ether * lockMultiplier30 / FULL_PERCENT, 1);
    }

    function test_getRewards() public {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit1 = 100 ether;
        uint256 bobLockAmountDeposit1 = 300 ether;

        _lock(alice, aliceLockAmountDeposit1, lockPeriod30);
        _lock(bob, bobLockAmountDeposit1, lockPeriod30);
        _emitFees(reward1Amount);

        uint256 reward2Amount = 50 * 1e6;
        uint256 aliceLockAmountDeposit2 = 200 ether;
        uint256 bobLockAmountDeposit2 = 200 ether;

        // ACT
        _lock(alice, aliceLockAmountDeposit2, lockPeriod30);
        _lock(bob, bobLockAmountDeposit2, lockPeriod30);
        _emitFees(reward2Amount);

        // ASSERT
        vm.startPrank(alice);
        assertApproxEqAbs(_KSULocking.getRewards(alice), 25 * 1e6 + 1875 * 1e4, 1);
        vm.stopPrank();
        vm.startPrank(bob);
        assertApproxEqAbs(_KSULocking.getRewards(bob), 75 * 1e6 + 3125 * 1e4, 1);
        vm.stopPrank();
    }

    function test_emergencyWithdraw() public {
        // ARRANGE
        uint256 alice_lockId_1 = _lock(alice, 100 ether, lockPeriod30);
        uint256 alice_lockId_2 = _lock(alice, 200 ether, lockPeriod30);
        uint256 bob_lockId_1 = _lock(bob, 300 ether, lockPeriod30);
        uint256 bob_lockId_2 = _lock(bob, 200 ether, lockPeriod30);
        uint256 carol_lockId_1 = _lock(carol, 50 ether, lockPeriod30);
        uint256 david_lockId_1 = _lock(david, 500 ether, lockPeriod30);

        // ACT
        EmergencyWithdrawInput[] memory emergencyWithdrawInput = new EmergencyWithdrawInput[](4);

        emergencyWithdrawInput[0] = EmergencyWithdrawInput(alice, alice_lockId_1, 40 ether);
        emergencyWithdrawInput[1] = EmergencyWithdrawInput(alice, alice_lockId_2, 100 ether);
        emergencyWithdrawInput[3] = EmergencyWithdrawInput(bob, bob_lockId_2, 100 ether);
        emergencyWithdrawInput[2] = EmergencyWithdrawInput(david, david_lockId_1, 500 ether);

        vm.prank(admin);
        _KSULocking.emergencyWithdraw(emergencyWithdrawInput, user10);

        // ASSERT
        assertEq(_ksu.balanceOf(user10), 740 ether);

        assertEq(_ksu.balanceOf(address(_KSULocking)), 610 ether);

        assertEq(_KSULocking.userLock(alice, alice_lockId_1).amount, 60 ether);
        assertEq(_KSULocking.userLock(alice, alice_lockId_2).amount, 100 ether);
        assertEq(_KSULocking.userLock(bob, bob_lockId_1).amount, 300 ether);
        assertEq(_KSULocking.userLock(bob, bob_lockId_2).amount, 100 ether);
        assertEq(_KSULocking.userLock(carol, carol_lockId_1).amount, 50 ether);
        assertEq(_KSULocking.userLock(david, david_lockId_1).amount, 0);
    }
}
