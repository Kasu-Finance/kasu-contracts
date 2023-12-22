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
        //assertApproxEqAbs(_usdc.balanceOf(address(alice)), 0, 1);
        _unlock(alice, 50 ether, 0);

        // assert Alice
        // A reward of 200 USC is emitted to Lock Contract
        // David locks 500 KSU for 360d
        // Alice locks 800 KSU for 180d
        // A reward of 600 USC is emitted to Lock Contract
        // 180d pass
        // Bob collect his rewards // USDC
        // Bob unlocks 1/3 of his locked amount // KSU
        // assert Bob
        // A reward of 400 USC is emitted to Lock Contract
        // 360d pass
        // David collect his rewards // USDC
        // David unlocks all of his locked amount // KSU
        // assert David
        // 360d pass
        // Carol collects her rewards // USDC
        // assert Carol
        // Everyone unlocks
        // assert everyone
    }
}
