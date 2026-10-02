// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

/**
 * @dev Active tranche bookkeeping (Base Tax Pay incident, epoch 121).
 *
 * On Base, `forceImmediateWithdrawal(TaxPay, Senior, user, 0)` (2025-08-29) ran for two users who no longer held
 * Senior shares. `removeUserActiveShares(user, 0)` saw `0 == 0` and removed the user a second time: it decremented
 * the user manager's bare active tranche counter again and evicted whichever user sat at index 0 of the Senior
 * tranche users array. One of those users later left a 1-share withdrawal request; accepting it underflowed the
 * counter and reverted the whole Tax Pay clearing.
 *
 * The fix keeps one membership check per side: the tranche lists a user iff `_isTrancheUser`, and the user
 * manager counts a (user, tranche) pair iff its flag is set, with add/remove idempotent per pair.
 */
contract UserActiveTrancheCountTest is LendingPoolTestUtils {
    // Storage slots used only to simulate the desynced on-chain state; `test_storageSlots_matchViews` pins them.
    uint256 private constant TRANCHE_SHARES_SLOT = 4; // LendingPoolTranche.userActiveShares
    uint256 private constant TRANCHE_INDEX_SLOT = 5; // LendingPoolTranche._userArrayIndex
    uint256 private constant TRANCHE_USERS_SLOT = 6; // LendingPoolTranche._trancheUsers
    uint256 private constant UM_FLAG_SLOT = 8; // UserManager._isUserActiveInTranche
    uint256 private constant UM_COUNT_SLOT = 9; // UserManager._activeTrancheCount

    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    // ------------------------------------------------------------------ helpers

    function _count(address user) private view returns (uint256) {
        return userManager.userActiveTrancheCount(user);
    }

    function _listed(address tranche, address user) private view returns (bool) {
        return ILendingPoolTranche(tranche).isTrancheUser(user);
    }

    function _listedCount(address tranche) private view returns (uint256) {
        return ILendingPoolTranche(tranche).trancheUserCount();
    }

    function _shares(address tranche, address user) private view returns (uint256) {
        return ILendingPoolTranche(tranche).userActiveShares(user);
    }

    function _deposit(LendingPoolDeployment memory lpd, address user, uint256 trancheIndex, uint256 amount) private {
        uint256 dNftId = _requestDeposit(user, lpd.lendingPool, lpd.tranches[trancheIndex], amount);
        _acceptDepositRequest(lpd.lendingPool, dNftId, amount);
    }

    function _usersBase() private pure returns (uint256) {
        return uint256(keccak256(abi.encode(TRANCHE_USERS_SLOT)));
    }

    /// @dev Removes `user` from the array the way the old zero-share removal did (array only, index left stale).
    function _evict(address tranche, address user) private {
        uint256 n = _listedCount(tranche);
        uint256 index = uint256(vm.load(tranche, keccak256(abi.encode(user, TRANCHE_INDEX_SLOT))));
        address last = address(uint160(uint256(vm.load(tranche, bytes32(_usersBase() + n - 1)))));
        vm.store(tranche, bytes32(_usersBase() + index), bytes32(uint256(uint160(last))));
        vm.store(tranche, keccak256(abi.encode(last, TRANCHE_INDEX_SLOT)), bytes32(index));
        vm.store(tranche, bytes32(TRANCHE_USERS_SLOT), bytes32(n - 1));
    }

    /// @dev Clears the user manager record of (user, tranche), as in the state left on-chain before the backfill.
    function _clearUserManagerRecord(address user, address tranche) private {
        vm.store(address(userManager), keccak256(abi.encode(tranche, keccak256(abi.encode(user, UM_FLAG_SLOT)))), 0);
        vm.store(address(userManager), keccak256(abi.encode(user, UM_COUNT_SLOT)), 0);
    }

    // ------------------------------------------------------------------ layout guard

    /// Fails if a layout change moves any slot the tests write to.
    function test_storageSlots_matchViews() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);

        assertEq(uint256(vm.load(mezz, keccak256(abi.encode(alice, TRANCHE_SHARES_SLOT)))), _shares(mezz, alice));
        assertEq(uint256(vm.load(mezz, bytes32(TRANCHE_USERS_SLOT))), _listedCount(mezz));
        uint256 index = uint256(vm.load(mezz, keccak256(abi.encode(alice, TRANCHE_INDEX_SLOT))));
        assertEq(index, 1);
        assertEq(address(uint160(uint256(vm.load(mezz, bytes32(_usersBase() + index))))), alice);

        bytes32 flagSlot = keccak256(abi.encode(mezz, keccak256(abi.encode(alice, UM_FLAG_SLOT))));
        assertEq(uint256(vm.load(address(userManager), flagSlot)), 1);
        assertTrue(userManager.isUserActiveInTranche(alice, mezz));
        assertEq(uint256(vm.load(address(userManager), keccak256(abi.encode(alice, UM_COUNT_SLOT)))), _count(alice));
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

        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, senior, alice, _shares(senior, alice));
        assertEq(_count(alice), 1);

        // the 2025-08-29 call: zero shares on a tranche alice no longer holds
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, senior, alice, 0);

        assertEq(_count(alice), 1, "zero-share redeem must not decrement");
        assertEq(_listedCount(senior), 1, "zero-share redeem must not evict");
        assertTrue(_listed(senior, bob));

        address mezz = lpd.tranches[1];
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));
        assertEq(_count(alice), 0);
    }

    function test_zeroShareForcedWithdrawal_holderUnchanged() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        uint256 shares = _shares(mezz, alice);

        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, 0);

        assertEq(_shares(mezz, alice), shares);
        assertEq(_count(alice), 1);
        assertEq(_listedCount(mezz), 1);
    }

    // ------------------------------------------------------------------ user manager: idempotent per (user, tranche)

    /// The live K-1 state: accepting a withdrawal that empties a position the user manager does not record.
    /// Before the fix this reverted with Panic(0x11) and took the whole clearing with it.
    function test_acceptWithdrawal_unrecordedPosition_emitsAndDoesNotRevert() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        uint256 shares = _shares(mezz, alice);
        uint256 wNftId = _requestWithdrawal(alice, lpd.lendingPool, mezz, shares);

        _clearUserManagerRecord(alice, mezz);

        vm.expectEmit(true, true, true, true, address(userManager));
        emit IUserManager.UserActiveTrancheCountUnderflow(alice, lpd.lendingPool, mezz);
        _acceptWithdrawalRequest(lpd.lendingPool, wNftId, shares);

        assertEq(_shares(mezz, alice), 0);
        assertEq(_count(alice), 0);
        assertEq(_listedCount(mezz), 0);
    }

    function test_addUserActiveTranche_isIdempotentPerTranche() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        vm.startPrank(lpd.tranches[0]);
        userManager.addUserActiveTranche(carol, lpd.lendingPool);
        userManager.addUserActiveTranche(carol, lpd.lendingPool);
        vm.stopPrank();
        assertEq(_count(carol), 1, "a second add for the same tranche is a no-op");

        vm.prank(lpd.tranches[1]);
        userManager.addUserActiveTranche(carol, lpd.lendingPool);
        assertEq(_count(carol), 2);

        vm.startPrank(lpd.tranches[0]);
        userManager.removeUserActiveTranche(carol, lpd.lendingPool);
        vm.expectEmit(true, true, true, true, address(userManager));
        emit IUserManager.UserActiveTrancheCountUnderflow(carol, lpd.lendingPool, lpd.tranches[0]);
        userManager.removeUserActiveTranche(carol, lpd.lendingPool);
        vm.stopPrank();
        assertEq(_count(carol), 1, "a second remove for the same tranche is a no-op");
    }

    function test_removeUserActiveTranche_onlyTranche() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        vm.expectRevert();
        vm.prank(carol);
        userManager.removeUserActiveTranche(carol, lpd.lendingPool);
    }

    function test_syncUserActiveTranche_derivesFromShares() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _clearUserManagerRecord(alice, mezz);
        assertEq(_count(alice), 0);

        vm.startPrank(carol); // permissionless
        userManager.syncUserActiveTranche(alice, lpd.lendingPool, mezz);
        userManager.syncUserActiveTranche(alice, lpd.lendingPool, mezz);
        userManager.syncUserActiveTranche(alice, lpd.lendingPool, lpd.tranches[0]); // holds nothing there
        vm.stopPrank();
        assertEq(_count(alice), 1);
        assertTrue(userManager.isUserActiveInTranche(alice, mezz));
        assertFalse(userManager.isUserActiveInTranche(alice, lpd.tranches[0]));

        // a record without shares is cleared
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));
        vm.prank(lpd.tranches[0]);
        userManager.addUserActiveTranche(alice, lpd.lendingPool); // bogus record
        assertEq(_count(alice), 1);
        userManager.syncUserActiveTranche(alice, lpd.lendingPool, lpd.tranches[0]);
        assertEq(_count(alice), 0);
    }

    function test_syncUserActiveTranche_rejectsForeignTranche() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        LendingPoolDeployment memory other = _createDefaultLendingPool();
        vm.expectRevert(
            abi.encodeWithSelector(ILendingPoolErrors.InvalidTranche.selector, lpd.lendingPool, other.tranches[0])
        );
        userManager.syncUserActiveTranche(alice, lpd.lendingPool, other.tranches[0]);
    }

    /// The upgrade backfill: the new per-tranche records start empty and are rebuilt from on-chain shares.
    function test_backfill_rebuildsRecordsFromShares() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 2, 100 * 10 ** 6);
        _deposit(lpd, bob, 2, 100 * 10 ** 6);
        _clearUserManagerRecord(alice, lpd.tranches[1]);
        _clearUserManagerRecord(alice, lpd.tranches[2]);
        _clearUserManagerRecord(bob, lpd.tranches[2]);

        ILendingPoolTranche(lpd.tranches[1]).syncTrancheUser(alice);
        ILendingPoolTranche(lpd.tranches[2]).syncTrancheUser(alice);
        ILendingPoolTranche(lpd.tranches[2]).syncTrancheUser(bob);

        assertEq(_count(alice), 2);
        assertEq(_count(bob), 1);
        assertEq(_listedCount(lpd.tranches[2]), 2, "listed users unchanged");
    }

    // ------------------------------------------------------------------ tranche users array: one membership check

    /// An evicted user (out of the array, stale index pointing at someone else) leaves without evicting anyone.
    function test_exitWhileNotListed_doesNotEvictOthers() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6); // index 0
        _deposit(lpd, alice, 1, 100 * 10 ** 6); // index 1
        _deposit(lpd, carol, 1, 100 * 10 ** 6); // index 2
        _evict(mezz, alice); // carol moves to index 1; alice's index stays 1

        vm.expectEmit(true, true, true, true, mezz);
        emit ILendingPoolTranche.TrancheUserNotInArray(alice);
        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));

        assertEq(_listedCount(mezz), 2);
        assertTrue(_listed(mezz, bob));
        assertTrue(_listed(mezz, carol));
        assertEq(_count(alice), 0);
    }

    function test_syncTrancheUser_restoresMissingHolderOnce() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _evict(mezz, alice);
        assertFalse(_listed(mezz, alice));

        vm.expectEmit(true, true, true, true, mezz);
        emit ILendingPoolTranche.TrancheUserRestored(alice, 1);
        vm.prank(carol); // permissionless
        ILendingPoolTranche(mezz).syncTrancheUser(alice);

        ILendingPoolTranche(mezz).syncTrancheUser(alice);
        ILendingPoolTranche(mezz).syncTrancheUser(bob);
        ILendingPoolTranche(mezz).syncTrancheUser(carol);
        assertEq(_listedCount(mezz), 2);
        assertTrue(_listed(mezz, alice));
        assertEq(_count(alice), 1, "count untouched: the record was already right");

        _forceImmediateWithdrawal(poolManagerAccount, lpd.lendingPool, mezz, alice, _shares(mezz, alice));
        assertEq(_listedCount(mezz), 1);
        assertTrue(_listed(mezz, bob));
    }

    /// An evicted holder who deposits again is re-listed exactly once, and the count does not move.
    function test_depositWhileNotListed_relistsOnce() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _evict(mezz, alice);

        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);

        assertEq(_listedCount(mezz), 2);
        assertTrue(_listed(mezz, alice));
        assertEq(_count(alice), 1);
    }

    /// Finding 2: a listed user holding zero shares must not be pushed a second time on a new deposit (the old
    /// `userActiveShares == 0` check did), which would mint loss receipt tokens to that user twice.
    function test_depositWhileListedWithZeroShares_noDoublePush() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        // a listed user with zero active shares
        vm.store(mezz, keccak256(abi.encode(alice, TRANCHE_SHARES_SLOT)), 0);
        assertTrue(_listed(mezz, alice));

        _deposit(lpd, alice, 1, 100 * 10 ** 6);

        assertEq(_listedCount(mezz), 2, "no second entry for alice");
        assertTrue(_listed(mezz, alice));
    }

    function test_syncTrancheUser_removesListedUserWithoutShares() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        vm.store(mezz, keccak256(abi.encode(alice, TRANCHE_SHARES_SLOT)), 0);

        vm.expectEmit(true, true, true, true, mezz);
        emit ILendingPoolTranche.TrancheUserRemoved(alice);
        ILendingPoolTranche(mezz).syncTrancheUser(alice);

        assertEq(_listedCount(mezz), 1);
        assertTrue(_listed(mezz, bob));
        assertEq(_count(alice), 0, "record follows the shares");
    }

    /// Loss receipts reach every holder exactly once after a repair.
    function test_lossReceipts_afterRepair_eachHolderOnce() public {
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();
        address mezz = lpd.tranches[1];
        _deposit(lpd, bob, 1, 100 * 10 ** 6);
        _deposit(lpd, alice, 1, 100 * 10 ** 6);
        _evict(mezz, alice);
        ILendingPoolTranche(mezz).syncTrancheUser(alice);
        ILendingPoolTranche(mezz).syncTrancheUser(alice);

        _drawFunds(lpd.lendingPool, 200 * 10 ** 6); // a loss can only hit drawn funds
        uint256 lossId = _reportLoss(poolFundsManagerAccount, lpd.lendingPool, 10 * 10 ** 6, true);
        assertGt(_shares(mezz, alice), 0);

        assertEq(IERC1155(mezz).balanceOf(alice, lossId), _shares(mezz, alice));
        assertEq(IERC1155(mezz).balanceOf(bob, lossId), _shares(mezz, bob));
    }
}
