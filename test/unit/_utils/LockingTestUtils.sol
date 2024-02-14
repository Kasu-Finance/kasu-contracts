// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./BaseTestUtils.sol";
import "../../shared/MockERC20Permit.sol";
import "../../shared/MockUSDC.sol";
import "../../../src/locking/KSULockBonus.sol";
import "../../../src/locking/KSULocking.sol";
import "../../../src/shared/access/KasuController.sol";

contract LockingTestUtils is BaseTestUtils {
    ERC20Permit internal _ksu;
    IERC20 internal _usdc;

    KasuController internal _kasuController;
    KSULocking internal _KSULocking;
    KSULockBonus internal _KSULockBonus;

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

    function __locking_setUp() internal virtual {
        MockERC20Permit mockKsu = new MockERC20Permit("KSU", "KSU", 18);
        MockUSDC mockUsdc = new MockUSDC();
        __locking_setUp(mockKsu, mockUsdc);
    }

    function __locking_setUp(ERC20Permit ksu, IERC20 usdc) internal virtual {
        _ksu = ksu;
        _usdc = usdc;

        KasuController kasuControllerImpl = new KasuController();
        TransparentUpgradeableProxy kasuControllerProxy =
            new TransparentUpgradeableProxy(address(kasuControllerImpl), address(proxyAdmin), "");
        _kasuController = KasuController(address(kasuControllerProxy));

        startHoax(admin);
        _kasuController.initialize(admin, address(0));

        _KSULocking = new KSULocking(_kasuController);
        _KSULocking.initialize(_ksu, _usdc);

        _KSULocking.addLockPeriod(lockPeriod30, lockMultiplier30, ksuBonusMultiplier30);
        _KSULocking.addLockPeriod(lockPeriod180, lockMultiplier180, ksuBonusMultiplier180);
        _KSULocking.addLockPeriod(lockPeriod360, lockMultiplier360, ksuBonusMultiplier360);
        _KSULocking.addLockPeriod(lockPeriod720, lockMultiplier720, ksuBonusMultiplier720);

        vm.stopPrank();
    }

    // ###  Helper Functions ###

    function _lock(address sender, uint256 amount, uint256 lockPeriod_)
        internal
        prank(sender)
        returns (uint256 userLockId)
    {
        deal(address(_ksu), sender, amount, true);
        _ksu.approve(address(_KSULocking), amount);
        return _KSULocking.lock(amount, lockPeriod_);
    }

    function _emitFees(uint256 rewardAmount) internal prank(admin) {
        deal(address(_usdc), admin, rewardAmount, true);
        _usdc.approve(address(_KSULocking), rewardAmount);
        _KSULocking.emitFees(rewardAmount);
    }

    function _unlock(address sender, uint256 amount, uint256 userLockId) internal prank(sender) {
        _KSULocking.unlock(amount, userLockId);
    }

    function _unlockAll(address sender, uint256 userLockId) internal prank(sender) returns (uint256 totalAmount) {
        totalAmount = _KSULocking.userLock(sender, userLockId).amount;
        _KSULocking.unlock(totalAmount, userLockId);
    }

    function _claimFees(address sender) internal prank(sender) returns (uint256) {
        return _KSULocking.claimFees();
    }

    function _addBonusKSU(uint256 amount) internal prank(admin) {
        deal(address(_ksu), admin, amount, true);
        _ksu.transfer(address(_KSULockBonus), amount);
    }
}
