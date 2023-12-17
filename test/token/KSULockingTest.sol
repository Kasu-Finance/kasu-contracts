// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../src/token/KSULocking.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";
import "../../src/shared/Constants.sol";

contract KSULockingTest is Test {
    IERC20 private _ksu;
    IERC20 private _usdc;
    KSULocking private _KSULocking;

    address public admin = address(0xad);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 public lockPeriod = 30 days;
    uint256 public lockMultiplier = 105_00;

    function setUp() public {
        _ksu = new ERC20("KSU", "KSU");
        _usdc = new ERC20("USDC", "USDC");
        _KSULocking = new KSULocking();

        _KSULocking.initialize(_ksu, _usdc);

        deal(address(_ksu), alice, 1000 ether, true);
        deal(address(_ksu), bob, 1000 ether, true);
        deal(address(_usdc), admin, 1000 * 1e6, true);

        _KSULocking.addLockPeriod(lockPeriod, lockMultiplier);
    }

    function testEmitFees() public {
        // ARRANGE
        uint256 amount = 100 * 1e6;

        _approve(_usdc, admin, address(_KSULocking), amount);

        // ACT
        vm.startPrank(admin);
        _KSULocking.emitFees(amount);

        // ASSERT
        assertEq(_usdc.balanceOf(address(_KSULocking)), amount);
    }

    function testLock() public {
        // ARRANGE
        uint256 _lockAmount = 100 ether;

        _approve(_ksu, alice, address(_KSULocking), _lockAmount);

        // ACT
        vm.startPrank(alice);
        _KSULocking.lock(_lockAmount, lockPeriod);

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), _lockAmount);
        assertEq(_KSULocking.balanceOf(alice), _lockAmount * lockMultiplier / FULL_PERCENT);
    }

    function testLockRewards() public {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;
        uint256 _lockAmount = 200 ether;

        _approve(_ksu, alice, address(_KSULocking), _lockAmount);
        _approve(_usdc, admin, address(_KSULocking), rewardAmount);

        vm.prank(alice);
        _KSULocking.lock(_lockAmount, lockPeriod);
        vm.prank(admin);
        _KSULocking.emitFees(rewardAmount);

        // ASSERT
        assertEq(_ksu.balanceOf(address(_KSULocking)), _lockAmount);
        assertEq(_usdc.balanceOf(address(_KSULocking)), rewardAmount);

        // ACT
        vm.prank(alice);
        _KSULocking.claimFees();

        // ASSERT
        assertApproxEqAbs(_usdc.balanceOf(address(_KSULocking)), 0, 1);
        assertApproxEqAbs(_usdc.balanceOf(address(alice)), rewardAmount, 1);
    }

    function testLockRewardsForTwoUsersOneDeposit() public  {
        // ARRANGE
        uint256 rewardAmount = 100 * 1e6;
        uint256 aliceLockAmount = 100 ether;
        uint256 bobLockAmount = 300 ether;

        _lockAmount(alice, aliceLockAmount, lockPeriod);
        _lockAmount(bob, bobLockAmount, lockPeriod);
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

    function testLockRewardsForTwoUsersMultipleDepositsAndRewards() public  {
        // ARRANGE
        uint256 reward1Amount = 100 * 1e6;
        uint256 aliceLockAmountDeposit1 = 100 ether;
        uint256 bobLockAmountDeposit1 = 300 ether;

        _lockAmount(alice, aliceLockAmountDeposit1, lockPeriod);
        _lockAmount(bob, bobLockAmountDeposit1, lockPeriod);
        _emitFees(reward1Amount);

        uint256 reward2Amount = 50 * 1e6;
        uint256 aliceLockAmountDeposit2 = 200 ether;
        uint256 bobLockAmountDeposit2 = 200 ether;

        _lockAmount(alice, aliceLockAmountDeposit2, lockPeriod);
        _lockAmount(bob, bobLockAmountDeposit2, lockPeriod);
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

    function _approve(IERC20 token, address owner, address spender, uint256 amount) internal prank(owner) {
        token.approve(spender, amount);
    }

    modifier prank(address executor) {
        _prank(executor);
        _;
        vm.stopPrank();
    }

    function _prank(address executor) internal {
        if (executor.balance > 0) {
            vm.startPrank(executor);
        } else {
            vm.allowCheatcodes(executor);
            startHoax(executor);
        }
    }

    function _lockAmount(address sender, uint256 amount, uint256 lockPeriod) private  {
        _approve(_ksu, sender, address(_KSULocking), amount);
        vm.prank(sender);
        _KSULocking.lock(amount, lockPeriod);
    }

    function _emitFees(uint256 rewardAmount) private  {
        _approve(_usdc, admin, address(_KSULocking), rewardAmount);
        vm.prank(admin);
        _KSULocking.emitFees(rewardAmount);
    }
}
