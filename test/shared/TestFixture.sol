// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../src/shared/access/KasuController.sol";
import "../../src/locking/KSULocking.sol";
import "../../src/locking/KSULockBonus.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./MockERC20Permit.sol";

contract TestFixture is Test {
    IERC20 internal _ksu;
    IERC20 internal _usdc;

    KasuController internal _kasuController;
    KSULocking internal _KSULocking;
    KSULockBonus internal _KSULockBonus;

    address internal admin = address(0xad);
    address internal alice = address(0x1);
    address internal bob = address(0x2);

    uint256 internal lockPeriod30 = 30 days;
    uint256 internal lockMultiplier30 = 5_00;
    uint256 internal ksuBonusMultiplier30 = 0;

    uint256 internal lockPeriod180 = 180 days;
    uint256 internal lockMultiplier180 = 25_00;
    uint256 internal ksuBonusMultiplier180 = 10_00;

    uint256 internal lockPeriod360 = 360 days;
    uint256 internal lockMultiplier360 = 50_00;
    uint256 internal ksuBonusMultiplier360 = 25_00;

    uint256 internal lockPeriod720 = 720 days;
    uint256 internal lockMultiplier720 = 100_00;
    uint256 internal ksuBonusMultiplier720 = 70_00;

    function setupBase() internal virtual {
        _ksu = new MockERC20Permit("KSU", "KSU", 18);
        _usdc = new MockERC20Permit("USDC", "USDC", 6);

        ProxyAdmin proxy = new ProxyAdmin(admin);

        KasuController kasuControllerImpl = new KasuController();
        TransparentUpgradeableProxy kasuControllerProxy =
            new TransparentUpgradeableProxy(address(kasuControllerImpl), address(proxy), "");
        _kasuController = KasuController(address(kasuControllerProxy));

        startHoax(admin);
        _kasuController.initialize();

        _KSULocking = new KSULocking(_kasuController);
        _KSULocking.initialize(_ksu, _usdc);

        deal(address(_ksu), admin, 1000 ether, true);
        deal(address(_ksu), alice, 1000 ether, true);
        deal(address(_ksu), bob, 1000 ether, true);
        deal(address(_usdc), admin, 1000 * 1e6, true);

        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier30);
        _KSULocking.addLockPeriod(lockPeriod180, lockMultiplier180, ksuBonusMultiplier180);
        _KSULocking.addLockPeriod(lockPeriod360, lockMultiplier360, ksuBonusMultiplier360);
        _KSULocking.addLockPeriod(lockPeriod720, lockMultiplier720, ksuBonusMultiplier720);

        vm.stopPrank();
    }
}
