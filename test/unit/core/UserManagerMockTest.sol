// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "../../../src/core/interfaces/IUserLoyaltyRewards.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../_utils/BaseTestUtils.sol";
import "../../../src/core/UserManager.sol";
import "../../../src/core/interfaces/ISystemVariables.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPool.sol";
import "../../../src/locking/interfaces/IKSULocking.sol";

contract UserManagerMockTest is BaseTestUtils {
    ISystemVariables internal systemVariables;
    IKSULocking internal ksuLocking;
    UserManager internal userManager;
    address internal lendingPoolManager;

    address lendingPool1 = address(0x1111);
    address pendingPool1 = address(0x11ff);
    address lendingPool2 = address(0x2222);
    address pendingPool2 = address(0x22ff);
    address lendingPool3 = address(0x3333);
    address pendingPool3 = address(0x33ff);
    address lendingPool4 = address(0x4444);
    address pendingPool4 = address(0x44ff);

    uint256[] loyaltyThresholds;

    function setUp() public {
        ksuLocking = IKSULocking(address(0xeeee));
        systemVariables = ISystemVariables(address(0xffff));
        lendingPoolManager = address(0x1234);
        IUserLoyaltyRewards userLoyaltyRewards = IUserLoyaltyRewards(address(0x9999));

        UserManager userManagerImpl = new UserManager(systemVariables, ksuLocking, userLoyaltyRewards);
        TransparentUpgradeableProxy userManagerProxy =
            new TransparentUpgradeableProxy(address(userManagerImpl), address(proxyAdmin), "");
        userManager = UserManager(address(userManagerProxy));

        userManager.initialize(lendingPoolManager);

        vm.mockCall(address(ksuLocking), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));

        _mockDefaultLendingPool(lendingPool1, pendingPool1);
        _mockDefaultLendingPool(lendingPool2, pendingPool2);
        _mockDefaultLendingPool(lendingPool3, pendingPool3);
        _mockDefaultLendingPool(lendingPool4, pendingPool4);

        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.getCurrentEpochNumber.selector),
            abi.encode(0)
        );

        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.isClearingTime.selector),
            abi.encode(false)
        );

        vm.mockCall(
            address(userLoyaltyRewards),
            abi.encodeWithSelector(IUserLoyaltyRewards.emitUserLoyaltyReward.selector),
            abi.encode()
        );

        _mockKSUPrice(2e18);

        loyaltyThresholds = new uint256[](2);
        loyaltyThresholds[0] = 1_00;
        loyaltyThresholds[1] = 3_00;

        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.loyaltyThresholds.selector),
            abi.encode(loyaltyThresholds)
        );

        vm.mockCall(address(ksuLocking), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
    }

    function test_userRequestedDeposit() public {
        // ACT
        _userRequestedDeposit(alice, lendingPool1);
        _userRequestedDeposit(alice, lendingPool2);
        _userRequestedDeposit(alice, lendingPool2);

        // ASSERT
        address[] memory lendingPools = userManager.getUserLendingPools(alice);
        assertEq(lendingPools.length, 2);
        assertEq(lendingPools[0], lendingPool1);
        assertEq(lendingPools[1], lendingPool2);
    }

    function test_getUserLoyaltyLevel_defaultState_shouldReturnZero() public {
        // ACT
        (uint256 currentEpoch, uint256 loyaltyLevel) = userManager.getUserLoyaltyLevel(alice);

        // ASSERT
        assertEq(currentEpoch, 0);
        assertEq(loyaltyLevel, 0);
    }

    function test_getUserLoyaltyLevel1() public {
        // ARRANGE
        uint256 aliceAvailableBalance = 850 * 1e6;
        uint256 alicePendingDeposit = 150 * 1e6;
        uint256 aliceRKSU = 5 * 1e18;

        _mockUserLendingPoolBalance(alice, lendingPool1, aliceAvailableBalance, alicePendingDeposit);
        _mockRKSU(alice, aliceRKSU);

        _userRequestedDeposit(alice, lendingPool1);

        // ACT
        (uint256 currentEpoch, uint256 loyaltyLevel) = userManager.getUserLoyaltyLevel(alice);

        // ASSERT
        // 1000 USDC deposits
        // 10 USDC worth of rKSU
        // ratio = 1%

        assertEq(currentEpoch, 0);
        assertEq(loyaltyLevel, 1);
    }

    function test_getUserLoyaltyLevel2() public {
        // ARRANGE
        uint256 aliceAvailableBalance = 850 * 1e6;
        uint256 alicePendingDeposit = 150 * 1e6;
        uint256 aliceRKSU = 15 * 1e18;

        _mockUserLendingPoolBalance(alice, lendingPool1, aliceAvailableBalance, alicePendingDeposit);
        _mockRKSU(alice, aliceRKSU);

        _userRequestedDeposit(alice, lendingPool1);

        // ACT
        (uint256 currentEpoch, uint256 loyaltyLevel) = userManager.getUserLoyaltyLevel(alice);

        // ASSERT
        // 1000 USDC deposits
        // 30 USDC worth of rKSU
        // ratio = 3%

        assertEq(currentEpoch, 0);
        assertEq(loyaltyLevel, 2);
    }

    function test_updateUserLendingPools_removeUserIfItHasNoDeposits() public {
        // ARRANGE
        _userRequestedDeposit(alice, lendingPool1);
        _userRequestedDeposit(alice, lendingPool2);
        _userRequestedDeposit(alice, lendingPool3);
        _userRequestedDeposit(alice, lendingPool4);
        address[] memory allUsersBefore = userManager.getAllUsers();
        assertEq(allUsersBefore.length, 1);

        address[] memory userLendingPoolBefore = userManager.getUserLendingPools(alice);
        assertEq(userLendingPoolBefore.length, 4);

        // ACT
        userManager.updateUserLendingPools(0, 0);

        // ASSERT
        address[] memory allUsers = userManager.getAllUsers();
        assertEq(allUsers.length, 0);

        address[] memory userLendingPool = userManager.getUserLendingPools(alice);
        assertEq(userLendingPool.length, 0);
    }

    function test_updateUserLendingPools_removeMultipleUsers() public {
        // ARRANGE
        _userRequestedDeposit(alice, lendingPool1);
        _userRequestedDeposit(bob, lendingPool1);
        _userRequestedDeposit(carol, lendingPool1);
        address[] memory allUsersBefore = userManager.getAllUsers();
        assertEq(allUsersBefore.length, 3);

        // ACT
        userManager.updateUserLendingPools(0, 2);

        // ASSERT
        address[] memory allUsers = userManager.getAllUsers();
        assertEq(allUsers.length, 0);
    }

    function test_updateUserLendingPools_removeSelectedUsers() public {
        // ARRANGE
        _userRequestedDeposit(alice, lendingPool1);
        _userRequestedDeposit(alice, lendingPool1);

        _userRequestedDeposit(bob, lendingPool1);
        _userRequestedDeposit(bob, lendingPool2);

        _userRequestedDeposit(carol, lendingPool1);
        _userRequestedDeposit(carol, lendingPool4);

        _userRequestedDeposit(david, lendingPool1);
        _userRequestedDeposit(david, lendingPool2);
        _userRequestedDeposit(david, lendingPool3);

        _userRequestedDeposit(user5, lendingPool1);

        _mockUserLendingPoolBalance(bob, lendingPool1, 100 * 1e6, 0);
        _mockUserLendingPoolBalance(david, lendingPool2, 0, 100 * 1e6);
        _mockUserLendingPoolBalance(david, lendingPool3, 1, 0);

        // ACT
        userManager.updateUserLendingPools(3, 4);
        userManager.updateUserLendingPools(0, 2);

        // ASSERT
        address[] memory allUsers = userManager.getAllUsers();
        assertEq(allUsers.length, 2);
        assertEq(allUsers[0], david);
        assertEq(allUsers[1], bob);

        address[] memory userLendingPools = userManager.getUserLendingPools(alice);
        assertEq(userLendingPools.length, 0);

        userLendingPools = userManager.getUserLendingPools(bob);
        assertEq(userLendingPools.length, 1);
        assertEq(userLendingPools[0], lendingPool1);

        userLendingPools = userManager.getUserLendingPools(carol);
        assertEq(userLendingPools.length, 0);

        userLendingPools = userManager.getUserLendingPools(david);
        assertEq(userLendingPools.length, 2);
        assertEq(userLendingPools[0], lendingPool3);
        assertEq(userLendingPools[1], lendingPool2);

        userLendingPools = userManager.getUserLendingPools(user5);
        assertEq(userLendingPools.length, 0);
    }

    function test_updateUserLendingPools_revertIfCalledDuringClearing() public {
        // ARRANGE
        vm.mockCall(
            address(systemVariables), abi.encodeWithSelector(ISystemVariables.isClearingTime.selector), abi.encode(true)
        );

        // ACT & ASSERT
        vm.expectRevert(CannotExecuteDuringClearingTime.selector);
        userManager.updateUserLendingPools(0, 0);
    }

    function test_updateUserLendingPools_revertIfFromIndexIsMoreThanToIndex() public {
        // ARRANGE
        _userRequestedDeposit(alice, lendingPool1);
        _userRequestedDeposit(bob, lendingPool1);
        _userRequestedDeposit(carol, lendingPool1);
        _userRequestedDeposit(david, lendingPool1);

        // ACT & ASSERT
        vm.expectRevert(IUserManager.BadUserIndex.selector);
        userManager.updateUserLendingPools(3, 2);
    }

    function _userRequestedDeposit(address user, address lendingPool) internal prank(lendingPoolManager) {
        userManager.userRequestedDeposit(user, lendingPool);
    }

    function _mockDefaultLendingPool(address lendingPool, address pendingPool) internal {
        vm.mockCall(
            address(lendingPool), abi.encodeWithSelector(ILendingPool.getUserBalance.selector), abi.encode(uint256(0))
        );

        vm.mockCall(
            address(lendingPool), abi.encodeWithSelector(ILendingPool.getPendingPool.selector), abi.encode(pendingPool)
        );

        vm.mockCall(
            address(pendingPool),
            abi.encodeWithSelector(IPendingPool.getUserPendingDepositAmount.selector),
            abi.encode(uint256(0))
        );
    }

    function _mockUserLendingPoolBalance(
        address user,
        address lendingPool,
        uint256 userAvailableBalance,
        uint256 pendingDeposit
    ) internal {
        vm.mockCall(
            address(lendingPool), abi.encodeCall(ILendingPool.getUserBalance, (user)), abi.encode(userAvailableBalance)
        );

        address pendingPool = ILendingPool(lendingPool).getPendingPool();
        uint256 epochId = systemVariables.getCurrentEpochNumber() + 1;

        vm.mockCall(
            address(pendingPool),
            abi.encodeCall(IPendingPool.getUserPendingDepositAmount, (user, epochId)),
            abi.encode(pendingDeposit)
        );
    }

    function _mockRKSU(address user, uint256 rKSUBalance) internal {
        vm.mockCall(
            address(ksuLocking), abi.encodeWithSelector(IERC20.balanceOf.selector, user), abi.encode(rKSUBalance)
        );
    }

    function _mockKSUPrice(uint256 ksuPrice) internal {
        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.ksuEpochTokenPrice.selector),
            abi.encode(ksuPrice)
        );
    }
}
