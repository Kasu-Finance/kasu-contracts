// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../_utils/LendingPoolTestUtils.sol";

contract FeeManagerTest is LendingPoolTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
        __lendingPool_setUp();
    }

    function test_FeeManager() public {
        // ARRANGE
        vm.startPrank(admin);
        kasuController.grantRole(ROLE_PROTOCOL_FEE_CLAIMER, alice);

        systemVariables.setProtocolFeeReceiver(bob);
        uint256 ksuLockingBalanceBeforeFees = mockUsdc.balanceOf(address(_KSULocking));

        vm.mockCall(
            address(lendingPoolManager), abi.encodeCall(ILendingPoolManager.isLendingPool, (alice)), abi.encode(true)
        );

        // ACT1
        uint256 feeAmount = 1000 * 1e6;
        deal(address(mockUsdc), alice, feeAmount, true);
        _approve(mockUsdc, alice, address(feeManager), feeAmount);

        vm.startPrank(alice);
        feeManager.emitFees(feeAmount);

        // ASSERT1
        assertEq(ksuLockingBalanceBeforeFees, 0);
        assertEq(mockUsdc.balanceOf(address(_KSULocking)), 500 * 1e6);
        assertEq(mockUsdc.balanceOf(address(feeManager)), 500 * 1e6);

        // ACT2
        feeManager.claimProtocolFees();

        // ASSERT2
        assertEq(mockUsdc.balanceOf(address(feeManager)), 0);
        assertEq(mockUsdc.balanceOf(address(bob)), 500 * 1e6);

        // ACT3 & ASSERT3

        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILendingPoolErrors.InvalidLendingPool.selector, bob));
        feeManager.emitFees(feeAmount);
    }
}
