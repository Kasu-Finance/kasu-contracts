// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract KasuControllerTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_grantLendingPoolRole_wrongAdminAccount() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ACT / ASSERT
        vm.prank(admin);
        //        systemVariables.setPerformanceFee(10_05);
        //
        //        vm.startPrank(poolFundsManagerAccount);
        //        vm.expectRevert(
        //            abi.encodeWithSelector(
        //                IAccessControl.AccessControlUnauthorizedAccount.selector, poolFundsManagerAccount, ROLE_POOL_ADMIN
        //            )
        //        );
        //        systemVariables.setPerformanceFee(10_06);
        //        vm.stopPrank();
    }

    function test_revokeLendingPoolRole() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 amount = 100 * 1e6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, amount);

        // ACT / ASSERT
        vm.prank(lendingPoolAdminAccount);
        kasuController.revokeLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount);

        vm.startPrank(poolFundsManagerAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                poolFundsManagerAccount,
                ROLE_POOL_FUNDS_MANAGER
            )
        );
        lendingPoolManager.depositFirstLossCapital(lpd.lendingPool, amount);
        vm.stopPrank();
    }

    function test_renounceLendingPoolRole() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        // ACT / ASSERT
        uint256 amount = 100 * 1e6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, amount);

        // an account without the roles assigned to it, tries to renounce a role
        vm.prank(poolClearingManagerAccount);
        kasuController.renounceLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER);

        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, amount);

        // an account with the roles assigned to it, tries to renounce a role
        vm.prank(poolFundsManagerAccount);
        kasuController.renounceLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER);

        vm.startPrank(poolFundsManagerAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                poolFundsManagerAccount,
                ROLE_POOL_FUNDS_MANAGER
            )
        );
        lendingPoolManager.depositFirstLossCapital(lpd.lendingPool, amount);
        vm.stopPrank();
    }

    function test_pause_unpause() public {
        // ARRANGE
        // ACT
        // ASSERT
    }
}
