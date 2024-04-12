// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../_utils/LendingPoolTestUtils.sol";

contract KasuAllowlistTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_block() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ACT / ASSERT

        // alice in allowed list from setup
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);

        vm.prank(admin);
        kasuAllowList.blockUser(alice);

        // alice is blocked
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IKasuAllowList.UserBlocked.selector, alice));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6, "");

        vm.prank(admin);
        kasuAllowList.unblockUser(alice);

        // alice is unblocked
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], 4_000 * 1e6);
    }
}
