// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract KasuControllerTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_grantLendingPoolRole_wrongAdminAccount() public {
        // ARRANGE

        // ACT / ASSERT
        vm.prank(admin);
        systemVariables.setPerformanceFee(10_05);

        vm.startPrank(poolFundsManagerAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, poolFundsManagerAccount, ROLE_KASU_ADMIN
            )
        );
        systemVariables.setPerformanceFee(10_06);
        vm.stopPrank();
    }

    function test_revokeLendingPoolRole() public {
        // ARRANGE
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 amount = 100 * 1e6;
        _depositFirstLossCapital(poolFundsManagerAccount, lpd.lendingPool, amount);

        // ACT / ASSERT

        // revoking with an account that is neither admin or pool admin
        vm.startPrank(poolFundsManagerAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, poolFundsManagerAccount, ROLE_POOL_ADMIN
            )
        );
        kasuController.revokeLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount);
        vm.stopPrank();

        // revoking with an account that admin role
        vm.prank(admin);
        kasuController.revokeLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount);

        vm.prank(admin);
        kasuController.grantRole(ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount);

        // revoking with an account that has pool admin role works
        vm.prank(lendingPoolAdminAccount);
        kasuController.revokeLendingPoolRole(lpd.lendingPool, ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount);

        // poolFundsManagerAccount tries to depositFirstLossCapital after his role is revoked
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
        LendingPoolDeployment memory lpd = _createDefaultLendingPool();

        uint256 amount = 100 * 1e6;
        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], amount);

        // ACT / ASSERT
        vm.prank(admin);
        kasuController.pause();

        deal(address(mockUsdc), alice, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        lendingPoolManager.requestDeposit(lpd.lendingPool, lpd.tranches[0], amount, "", 0, "");

        vm.prank(admin);
        kasuController.unpause();

        _requestDeposit(alice, lpd.lendingPool, lpd.tranches[0], amount);
    }
}
