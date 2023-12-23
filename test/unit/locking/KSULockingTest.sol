// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../shared/TestFixture.sol";
import "../../shared/SigUtilsERC20.sol";
import "../../../src/locking/KSULockBonus.sol";
import "../../../src/locking/interfaces/IKSULocking.sol";
import "../../../src/shared/Constants.sol";
import "../../../src/shared/access/Roles.sol";

contract KSULockingTest is TestFixture {
    function setUp() public {
        setupBase();
    }

    function testAddLockPeriod_WhenNotAdmin_ShouldRevert() public {
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier30);
    }

    function testEmitFees() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;

        // ACT / ASSERT
        vm.startPrank(admin);
        _usdc.approve(address(_KSULocking), rewardAmount);
        vm.expectEmit(true, false, false, true, address(_KSULocking));
        emit FeesEmitted(address(admin), rewardAmount);
        deal(address(_usdc), admin, rewardAmount, true);
        _KSULocking.emitFees(rewardAmount);
        vm.stopPrank();

        // ASSERT
        assertEq(_usdc.balanceOf(address(_KSULocking)), rewardAmount);
    }

    function testLock() public {
        // ARRANGE
        uint256 aliceLockAmount = 100 ether;

        // ACT
        startHoax(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit UserLocked(address(alice), 0, aliceLockAmount, 0 ether);
        deal(address(_ksu), alice, aliceLockAmount, true);
        _KSULocking.lock(aliceLockAmount, lockPeriod30);

        // ASSERT
        uint256 aliceExpectedLockAmount = aliceLockAmount * lockMultiplier30 / FULL_PERCENT;
        assertEq(_ksu.balanceOf(address(_KSULocking)), aliceLockAmount);
        assertEq(_KSULocking.balanceOf(alice), aliceExpectedLockAmount);
    }

    function testLockWithPermit() public {
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

    function testLockWithBonusKSU() public {
        // ARRANGE
        _KSULockBonus = new KSULockBonus();
        _KSULockBonus.initialize(address(_KSULocking), _ksu);
        _KSULocking.setKSULockBonus(address(_KSULockBonus));
        _addBonusKSU(1000 ether);

        // ACT / ASSER
        uint256 aliceLockAmount = 100 ether;
        uint256 expectedAliceBaseKSULockAmount = 100 ether;
        uint256 expectedAliceBonusKSULockAmount = 10 ether;

        vm.startPrank(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit UserLocked(address(alice), 0, expectedAliceBaseKSULockAmount, expectedAliceBonusKSULockAmount);
        deal(address(_ksu), alice, aliceLockAmount, true);
        _KSULocking.lock(aliceLockAmount, lockPeriod180);
        vm.stopPrank();

        uint256 bobLockAmount = 200 ether;
        uint256 expectedBobBaseKSULockAmount = 200 ether;
        uint256 expectedBobBonusKSULockAmount = 50 ether;

        vm.startPrank(bob);
        _ksu.approve(address(_KSULocking), bobLockAmount);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit UserLocked(address(bob), 0, expectedBobBaseKSULockAmount, expectedBobBonusKSULockAmount);
        deal(address(_ksu), bob, bobLockAmount, true);
        _KSULocking.lock(bobLockAmount, lockPeriod360);
        vm.stopPrank();

        // ASSERT
        uint256 aliceExpectedLockedRKSUAmount =
            (expectedAliceBaseKSULockAmount + expectedAliceBonusKSULockAmount) * lockMultiplier180 / FULL_PERCENT;
        assertEq(_KSULocking.balanceOf(alice), aliceExpectedLockedRKSUAmount);

        uint256 bobExpectedLockedRKSUAmount =
            (expectedBobBaseKSULockAmount + expectedBobBonusKSULockAmount) * lockMultiplier360 / FULL_PERCENT;
        assertEq(
            _ksu.balanceOf(address(_KSULocking)),
            expectedBobBaseKSULockAmount + expectedBobBonusKSULockAmount + expectedAliceBaseKSULockAmount
                + expectedAliceBonusKSULockAmount
        );
        assertEq(_KSULocking.balanceOf(bob), bobExpectedLockedRKSUAmount);
    }

    function testLockRewards() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;
        uint256 aliceLockAmount = 200 ether;

        _lock(alice, aliceLockAmount, lockPeriod30);
        _emitFees(rewardAmount);

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), aliceLockAmount);
        assertEq(_usdc.balanceOf(address(_KSULocking)), rewardAmount);

        // ACT
        vm.startPrank(alice);
        vm.expectEmit();
        emit FeesClaimed(address(alice), rewardAmount);
        _KSULocking.claimFees();
        vm.stopPrank();

        // ASSERT
        assertApproxEqAbs(_usdc.balanceOf(address(_KSULocking)), 0, 1);
        assertApproxEqAbs(_usdc.balanceOf(address(alice)), rewardAmount, 1);
    }

    function testLockRewardsForTwoUsersOneDeposit() public {
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
        assertApproxEqAbs(_usdc.balanceOf(address(alice)), 25 * 1e6, 1);
        assertApproxEqAbs(_usdc.balanceOf(address(bob)), 75 * 1e6, 1);
    }

    function testLockRewardsForTwoUsersMultipleDepositsAndRewards() public {
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
        assertApproxEqAbs(_usdc.balanceOf(address(alice)), 25 * 1e6 + 1875 * 1e4, 1);
        assertApproxEqAbs(_usdc.balanceOf(address(bob)), 75 * 1e6 + 3125 * 1e4, 1);
    }

    function testUnlock() public {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit1 = 100 ether;

        _lock(alice, aliceLockAmountDeposit1, lockPeriod30);
        _emitFees(reward1Amount);

        skip(lockPeriod30);

        // ACT / ASSET
        uint256 aliceUnLockAmount = 80 ether;

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, false, address(_KSULocking));
        emit UserUnlocked(address(alice), 0, aliceUnLockAmount);
        _KSULocking.unlock(aliceUnLockAmount, 0);
        vm.stopPrank();
    }

    function testUnlockWhenNotExpired_ShouldRevert() public {
        // ARRANGE
        uint256 aliceLockAmountDeposit = 100 ether;

        uint256 lockId = _lock(alice, aliceLockAmountDeposit, lockPeriod30);

        // ACT / ASSET
        uint256 aliceUnLockAmount = 80 ether;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DepositLocked.selector, lockId));
        _KSULocking.unlock(aliceUnLockAmount, 0);
    }

    function testUnlockForTwoUsers() public {
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

    function testGetRewards() public {
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
}
