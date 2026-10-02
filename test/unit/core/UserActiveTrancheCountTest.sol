// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @dev Active tranche count and tranche users array bookkeeping (Base Tax Pay incident, epoch 121).
 *
 * On Base, a batch of `forceImmediateWithdrawal(TaxPay, Senior, user, 0)` calls (2025-08-29) ran for two
 * users who no longer held Senior shares. `removeUserActiveShares(user, 0)` saw `0 == 0`, removed the user
 * a second time: it decremented `UserManager._userActiveTrancheCount[user]` again and evicted whichever
 * user sat at index 0 of the Senior tranche users array. One of those users later left a 1-share
 * withdrawal request; accepting it underflowed the count and reverted the whole Tax Pay clearing.
 */
contract UserActiveTrancheCountTest is LendingPoolTestUtils {
    uint256 private constant COUNT_SLOT = 7; // UserManager._userActiveTrancheCount
    uint256 private constant INDEX_SLOT = 5; // LendingPoolTranche._userArrayIndex
    uint256 private constant USERS_SLOT = 6; // LendingPoolTranche._trancheUsers

    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    // ------------------------------------------------------------------ helpers

    function _count(address user) private view returns (uint256) {
        return uint256(vm.load(address(userManager), keccak256(abi.encode(user, COUNT_SLOT))));
    }

    function _setCount(address user, uint256 count) private {
        vm.store(address(userManager), keccak256(abi.encode(user, COUNT_SLOT)), bytes32(count));
    }

    function _trancheUsers(address tranche) private view returns (address[] memory users) {
        uint256 n = uint256(vm.load(tranche, bytes32(USERS_SLOT)));
        users = new address[](n);
        uint256 base = uint256(keccak256(abi.encode(USERS_SLOT)));
        for (uint256 i; i < n; ++i) {
            users[i] = address(uint160(uint256(vm.load(tranche, bytes32(base + i)))));
        }
    }

    function _deposit(LendingPoolDeployment memory lpd, address user, uint256 trancheIndex, uint256 amount) private {
        uint256 dNftId = _requestDeposit(user, lpd.lendingPool, lpd.tranches[trancheIndex], amount);
        _acceptDepositRequest(lpd.lendingPool, dNftId, amount);
    }

    function _shares(address tranche, address user) private view returns (uint256) {
        return ILendingPoolTranche(tranche).userActiveShares(user);
    }

    // ------------------------------------------------------------------ root cause

    /// Replays the Base sequence: full exit from a tranche, then a zero-share forced withdrawal on it.
    function test_zeroShareForcedWithdrawal_keepsCountAndTrancheUsers() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address senior = lpd.tranches[2];

        _deposit(lpd, bob, 2, 100 * 10 ** 6); // bob sits at index 0 of the senior tranche
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 2, 100 * 10 ** 6);
        assertEq(_count(alice), 2);
        assertEq(_trancheUsers(senior)[0], bob);

        // alice leaves the senior tranche in full
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, senior, alice, _shares(senior, alice));
        assertEq(_count(alice), 1);

        // the 2025-08-29 call: zero shares on a tranche alice no longer holds
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, senior, alice, 0);

        assertEq(_count(alice), 1, "zero-share redeem must not decrement the count");
        address[] memory users = _trancheUsers(senior);
        assertEq(users.length, 1, "zero-share redeem must not evict anyone");
        assertEq(users[0], bob);

        // alice's last exit reaches zero without an underflow
        address mezz = lpd.tranches[1];
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));
        assertEq(_count(alice), 0);
    }

    /// A zero-share redeem by a holder is a no-op too (shares and membership unchanged).
    function test_zeroShareForcedWithdrawal_holderUnchanged() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        uint256 shares = _shares(mezz, alice);

        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, 0);

        assertEq(_shares(mezz, alice), shares);
        assertEq(_count(alice), 1);
        assertEq(_trancheUsers(mezz).length, 1);
    }

    // ------------------------------------------------------------------ safe decrement

    /// The live K-1 state: a pending withdrawal whose acceptance empties the position of a user whose count is
    /// already 0. Before the fix this reverted with Panic(0x11) and took the whole clearing with it.
    function test_acceptWithdrawal_countAlreadyZero_emitsAndDoesNotRevert() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        uint256 shares = _shares(mezz, alice);
        uint256 wNftId = _requestWithdrawal(alice, lpd.lendingPool, mezz, shares);

        _setCount(alice, 0); // the desync left on-chain by the zero-share redeem

        vm.expectEmit(true, true, true, true, address(userManager));
        emit IUserManager.UserActiveTrancheCountUnderflow(alice, lpd.lendingPool, mezz);
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId, shares);

        assertEq(_shares(mezz, alice), 0);
        assertEq(_count(alice), 0);
        assertEq(_trancheUsers(mezz).length, 0);
    }

    function test_removeUserActiveTranche_atZero_skipsWithEvent() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        vm.expectEmit(true, true, true, true, address(userManager));
        emit IUserManager.UserActiveTrancheCountUnderflow(carol, lpd.lendingPool, lpd.tranches[0]);
        vm.prank(lpd.tranches[0]);
        userManager.removeUserActiveTranche(carol, lpd.lendingPool);

        assertEq(_count(carol), 0);
    }

    function test_removeUserActiveTranche_onlyTranche() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        vm.expectRevert();
        vm.prank(carol);
        userManager.removeUserActiveTranche(carol, lpd.lendingPool);
    }

    // ------------------------------------------------------------------ tranche users array

    /// A user whose recorded index points at someone else (evicted earlier) leaves without evicting that user.
    function test_exitWithStaleIndex_doesNotEvictOthers() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6); // index 0
        _deposit(lpd, alice, 1, 100 * 10 ** 6); // index 1
        _deposit(lpd, carol, 1, 100 * 10 ** 6); // index 2

        // simulate the on-chain state of an evicted user: alice out of the array, her index still 0
        uint256 base = uint256(keccak256(abi.encode(USERS_SLOT)));
        vm.store(mezz, bytes32(base + 1), bytes32(uint256(uint160(carol))));
        vm.store(mezz, bytes32(USERS_SLOT), bytes32(uint256(2)));
        vm.store(mezz, keccak256(abi.encode(carol, INDEX_SLOT)), bytes32(uint256(1)));
        vm.store(mezz, keccak256(abi.encode(alice, INDEX_SLOT)), bytes32(uint256(0)));

        vm.expectEmit(true, true, true, true, mezz);
        emit ILendingPoolTranche.TrancheUserIndexMismatch(alice, 0);
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));

        address[] memory users = _trancheUsers(mezz);
        assertEq(users.length, 2);
        assertEq(users[0], bob);
        assertEq(users[1], carol);
        assertEq(_count(alice), 0);
    }

    function test_syncTrancheUser_restoresMissingHolderOnce() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6); // index 0
        _deposit(lpd, alice, 1, 100 * 10 ** 6); // index 1

        // evict alice the way the zero-share redeem did (she keeps her shares, index left at 1)
        vm.store(mezz, bytes32(USERS_SLOT), bytes32(uint256(1)));

        vm.expectEmit(true, true, true, true, mezz);
        emit ILendingPoolTranche.TrancheUserRestored(alice, 1);
        ILendingPoolTranche(mezz).syncTrancheUser(alice);

        // idempotent: present users, non-holders and repeated calls change nothing
        vm.recordLogs();
        ILendingPoolTranche(mezz).syncTrancheUser(alice);
        ILendingPoolTranche(mezz).syncTrancheUser(bob);
        ILendingPoolTranche(mezz).syncTrancheUser(carol);
        assertEq(vm.getRecordedLogs().length, 0);

        address[] memory users = _trancheUsers(mezz);
        assertEq(users.length, 2);
        assertEq(users[0], bob);
        assertEq(users[1], alice);

        // and she can leave cleanly afterwards
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));
        users = _trancheUsers(mezz);
        assertEq(users.length, 1);
        assertEq(users[0], bob);
    }

    // ------------------------------------------------------------------ count repair

    function _userManagerProxyAdmin() private view returns (ProxyAdmin) {
        return ProxyAdmin(address(uint160(uint256(vm.load(address(userManager), ERC1967Utils.ADMIN_SLOT)))));
    }

    function _currentImpl() private view returns (address) {
        return address(uint160(uint256(vm.load(address(userManager), ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function test_setUserActiveTrancheCounts_onlyThroughUpgradeAndCall() public {
        address[] memory users = new address[](1);
        uint256[] memory counts = new uint256[](1);
        users[0] = alice;
        counts[0] = 2;

        vm.expectRevert(abi.encodeWithSelector(IUserManager.CallerNotProxyAdmin.selector, carol));
        vm.prank(carol);
        UserManager(address(userManager)).setUserActiveTrancheCounts(users, counts);

        ProxyAdmin pa = _userManagerProxyAdmin();
        vm.expectEmit(true, true, true, true, address(userManager));
        emit IUserManager.UserActiveTrancheCountSet(alice, 2);
        vm.prank(pa.owner());
        pa.upgradeAndCall(
            ITransparentUpgradeableProxy(address(userManager)),
            _currentImpl(),
            abi.encodeCall(UserManager.setUserActiveTrancheCounts, (users, counts))
        );
        assertEq(_count(alice), 2);
    }

    /// The v2 reinitializer was callable by anyone wherever it had not been run (XDC AUDD and XDC USDC).
    function test_reinitialize_onlyThroughUpgradeAndCall() public {
        address[] memory users = new address[](0);
        uint256[] memory counts = new uint256[](0);
        vm.expectRevert(abi.encodeWithSelector(IUserManager.CallerNotProxyAdmin.selector, carol));
        vm.prank(carol);
        UserManager(address(userManager)).reinitialize(users, counts);
    }
}
