// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/locking/KSULocking.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "../../../src/shared/Constants.sol";
import "../../../src/token/KSU.sol";
import "../../shared/SigUtilsERC20.sol";
import "forge-std/console2.sol";
import "../../../src/locking/KSULockBonus.sol";

contract KSULockingTest is Test {
    IERC20 private _ksu;
    IERC20 private _usdc;
    KSULocking private _KSULocking;
    KSULockBonus private _KSULockBonus;

    address public admin = address(0xad);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 public lockPeriod30 = 30 days;
    uint256 public lockMultiplier30 = 5_00;

    uint256 public lockPeriod180 = 180 days;
    uint256 public lockMultiplier180 = 25_00;

    uint256 public lockPeriod360 = 360 days;
    uint256 public lockMultiplier360 = 50_00;

    uint256 public lockPeriod720 = 720 days;
    uint256 public lockMultiplier720 = 100_00;

    uint256 public ksuBonusMultiplier = 25_00;

    function setUp() public {
        KSU ksu_ = new KSU();
        ksu_.initialize(address(admin));
        _ksu = IERC20(address(ksu_));
        _usdc = new ERC20("USDC", "USDC");
        _KSULocking = new KSULocking();

        _KSULocking.initialize(_ksu, _usdc);

        deal(address(_ksu), alice, 1000 ether, true);
        deal(address(_ksu), bob, 1000 ether, true);
        deal(address(_usdc), admin, 1000 * 1e6, true);

        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier);
        _KSULocking.addLockPeriod(lockPeriod180, lockMultiplier180, ksuBonusMultiplier);
        _KSULocking.addLockPeriod(lockPeriod360, lockMultiplier360, ksuBonusMultiplier);
        _KSULocking.addLockPeriod(lockPeriod720, lockMultiplier720, ksuBonusMultiplier);
    }

    function testEmitFees() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;

        // ACT / ASSERT
        vm.startPrank(admin);
        _usdc.approve(address(_KSULocking), rewardAmount);
        vm.expectEmit(true, false, false, true, address(_KSULocking));
        emit KSULocking.FeesEmitted(address(admin), rewardAmount);
        _KSULocking.emitFees(rewardAmount);
        vm.stopPrank();

        // ASSERT
        assertEq(_usdc.balanceOf(address(_KSULocking)), rewardAmount);
    }

    function testLock_() public {
        // ARRANGE
        uint256 aliceLockAmount = 100 ether;

        // ACT
        startHoax(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit KSULocking.UserLocked(address(alice), 0, aliceLockAmount, 0 ether);
        _KSULocking.lock(aliceLockAmount, lockPeriod30);

        // ASSERT
        uint256 aliceExpectedLockAmount = aliceLockAmount * lockMultiplier30 / FULL_PERCENT;
        assertEq(_ksu.balanceOf(address(_KSULocking)), aliceLockAmount);
        assertEq(_KSULocking.balanceOf(alice), aliceExpectedLockAmount);
    }

    function testLockWithPermit() public {
        // ARRANGE
        SigUtilsERC20 sigUtilsERC20 = new SigUtilsERC20(IERC20Permit(address(_ksu)).DOMAIN_SEPARATOR());

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
            nonce: IERC20Permit(address(_ksu)).nonces(user),
            deadline: deadline
        });

        bytes32 digest = sigUtilsERC20.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        hoax(user);
        _KSULocking.lockWithPermit(
            lockAmount, lockPeriod30, IKSULocking.ERC20Permit({value: lockAmount, deadline: deadline, v: v, r: r, s: s})
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
        vm.prank(admin);
        _ksu.transfer(address(_KSULockBonus), 1000 ether);

        // ACT / ASSER
        uint256 aliceLockAmount = 100 ether;
        uint256 expectedAliceBaseKSULockAmount = 100 ether;
        uint256 expectedAliceBonusKSULockAmount = 25 ether;

        vm.startPrank(alice);
        _ksu.approve(address(_KSULocking), aliceLockAmount);
        vm.expectEmit(true, true, false, true, address(_KSULocking));
        emit KSULocking.UserLocked(address(alice), 0, expectedAliceBaseKSULockAmount, expectedAliceBonusKSULockAmount);
        _KSULocking.lock(aliceLockAmount, lockPeriod30);
        vm.stopPrank();

        // ASSERT
        uint256 aliceExpectedLockedRKSUAmount =
            (expectedAliceBaseKSULockAmount + expectedAliceBonusKSULockAmount) * lockMultiplier30 / FULL_PERCENT;
        assertEq(_ksu.balanceOf(address(_KSULocking)), expectedAliceBaseKSULockAmount + expectedAliceBonusKSULockAmount);
        assertEq(_KSULocking.balanceOf(alice), aliceExpectedLockedRKSUAmount);
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
        emit KSULocking.FeesClaimed(address(alice), rewardAmount);
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
        vm.prank(alice);
        _KSULocking.claimFees();
        vm.prank(bob);
        _KSULocking.claimFees();

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

    function testUnlock_() public {
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
        emit KSULocking.UserUnlocked(address(alice), 0, aliceUnLockAmount);
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
        uint256 aliceUnLockAmount = 80 ether;
        vm.prank(alice);
        _KSULocking.unlock(aliceUnLockAmount, 0);

        uint256 bobUnLockAmount = 220 ether;
        vm.prank(bob);
        _KSULocking.unlock(bobUnLockAmount, 0);

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

    // ###  Helper Functions ###

    function _approve(IERC20 token, address owner, address spender, uint256 amount) internal prank(owner) {
        token.approve(spender, amount);
    }

    function _lock(address sender, uint256 amount, uint256 lockPeriod_)
        private
        prank(sender)
        returns (uint256 userLockId)
    {
        _ksu.approve(address(_KSULocking), amount);
        return _KSULocking.lock(amount, lockPeriod_);
    }

    function _emitFees(uint256 rewardAmount) private prank(admin) {
        _usdc.approve(address(_KSULocking), rewardAmount);
        _KSULocking.emitFees(rewardAmount);
    }

    function _prank(address executor) internal {
        if (executor.balance > 0) {
            vm.startPrank(executor);
        } else {
            startHoax(executor);
        }
    }

    modifier prank(address executor) {
        _prank(executor);
        _;
        vm.stopPrank();
    }
}
