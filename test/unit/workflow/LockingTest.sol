// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../shared/TestFixture.sol";
import "../../../src/token/KSU.sol";
import "../../shared/MockERC20Permit.sol";
import "../../../src/locking/KSULockBonus.sol";
import "forge-std/console2.sol";

contract LockingTest is TestFixture {
    function setUp() public {
        ProxyAdmin proxy = new ProxyAdmin(admin);
        KSU ksuImpl = new KSU();

        TransparentUpgradeableProxy ksuProxy = new TransparentUpgradeableProxy(address(ksuImpl), address(proxy), "");
        KSU _ksu = KSU(address(ksuProxy));
        _ksu.initialize(address(admin));

        MockERC20Permit _usdc = new MockERC20Permit("USDC", "USDC", 6);
        setupBase(ERC20Permit(address(_ksu)), _usdc);

        _KSULockBonus = new KSULockBonus();
        _KSULockBonus.initialize(address(_KSULocking), _ksu);
        _KSULocking.setKSULockBonus(address(_KSULockBonus));
    }

    function testCase1() public {
        vm.prank(admin);
        _ksu.transfer(address(_KSULockBonus), 300 ether);
        _lock(alice, 100 ether, lockPeriod30);
        _lock(bob, 400 ether, lockPeriod180);
        _emitFees(500 * 1e6);
        skip(lockPeriod30);
        _lock(carol, 500 ether, lockPeriod720);
        _claimFees(alice);
        assertApproxEqAbs(_ksu.balanceOf(address(_KSULocking)), 1300 ether, 1);
        //        assertApproxEqAbs(_usdc.balanceOf(address(alice)), 801526717600000000, 1);
        _unlock(alice, 50 ether, 0);
        // assert Alice
        // A reward of 200 USC is emitted to Lock Contract
        _emitFees(200 * 1e6);
        // David locks 500 KSU for 360d
        _lock(david, 400 ether, lockPeriod360);
        // Alice locks 800 KSU for 180d
        _lock(alice, 800 ether, lockPeriod180);
        // A reward of 600 USC is emitted to Lock Contract
        _emitFees(600 * 1e6);
        // 180d pass
        skip(lockPeriod180);
        // Bob collect his rewards // USDC
        _claimFees(bob);
        // Bob unlocks 200 of his locked amount // KSU
        _lock(bob, 200, lockPeriod720);
        // assert Bob
        // A reward of 400 USC is emitted to Lock Contract
        _emitFees(400 * 1e6);
        // 360d pass
        skip(lockPeriod360);
        // David collect his rewards // USDC
        _claimFees(david);
        // David unlocks all of his locked amount // KSU
        _unlockAll(david, 0);
        // assert David
        // 360d pass
        skip(lockPeriod360);
        // Carol collects her rewards // USDC
        _claimFees(carol);
        // assert Carol
        // Everyone unlocks
        _unlockAll(alice, 0);
        _unlockAll(alice, 1);
        _unlockAll(bob, 0);
        _unlockAll(bob, 1);
        _unlockAll(carol, 0);
        // assert everyone
    }
}
