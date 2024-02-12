// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../../shared/BaseTestUtils.sol";
import "../../../src/core/UserManager.sol";
import "../../../src/core/interfaces/ISystemVariables.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPool.sol";
import "../../../src/locking/interfaces/IKSULocking.sol";

contract UserManagerTest is BaseTestUtils {
    ISystemVariables internal systemVariables;
    IKSULocking internal ksuLocking;
    UserManager internal userManager;

    address lendingPool1 = address(0x1111);
    address pendingPool1 = address(0x11ff);
    address lendingPool2 = address(0x2222);
    address pendingPool2 = address(0x22ff);

    uint256[] loyaltyThresholds;

    function setUp() public {
        ksuLocking = IKSULocking(address(0xeeee));
        systemVariables = ISystemVariables(address(0xffff));

        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

        UserManager userManagerImpl = new UserManager(systemVariables, ksuLocking);
        TransparentUpgradeableProxy userManagerProxy =
            new TransparentUpgradeableProxy(address(userManagerImpl), address(proxyAdmin), "");
        userManager = UserManager(address(userManagerProxy));

        vm.mockCall(address(ksuLocking), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));

        vm.mockCall(
            address(lendingPool1),
            abi.encodeWithSelector(ILendingPool.getPendingPool.selector),
            abi.encode(pendingPool1)
        );

        vm.mockCall(
            address(lendingPool2),
            abi.encodeWithSelector(ILendingPool.getPendingPool.selector),
            abi.encode(pendingPool2)
        );

        _mockLendingPool(lendingPool1, 0, 0, 0);
        _mockLendingPool(lendingPool2, 0, 0, 0);

        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.getCurrentEpochNumber.selector),
            abi.encode(0)
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
        userManager.userRequestedDeposit(alice, lendingPool1);
        userManager.userRequestedDeposit(alice, lendingPool2);
        userManager.userRequestedDeposit(alice, lendingPool2);

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
        uint256 alicePendingWithdrawal = 50 * 1e6;
        uint256 aliceRKSU = 5 * 1e6;

        _mockLendingPool(lendingPool1, aliceAvailableBalance, alicePendingDeposit, alicePendingWithdrawal);
        _mockRKSU(alice, aliceRKSU);

        userManager.userRequestedDeposit(alice, lendingPool1);

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
        uint256 alicePendingWithdrawal = 50 * 1e6;
        uint256 aliceRKSU = 15 * 1e6;

        _mockLendingPool(lendingPool1, aliceAvailableBalance, alicePendingDeposit, alicePendingWithdrawal);
        _mockRKSU(alice, aliceRKSU);

        userManager.userRequestedDeposit(alice, lendingPool1);

        // ACT
        (uint256 currentEpoch, uint256 loyaltyLevel) = userManager.getUserLoyaltyLevel(alice);

        // ASSERT
        // 1000 USDC deposits
        // 30 USDC worth of rKSU
        // ratio = 3%

        assertEq(currentEpoch, 0);
        assertEq(loyaltyLevel, 2);
    }

    function _mockLendingPool(
        address lendingPool,
        uint256 userAvailableBalance,
        uint256 pendingDeposit,
        uint256 pendingWithdrawal
    ) internal {
        vm.mockCall(
            address(lendingPool),
            abi.encodeWithSelector(ILendingPool.getUserAvailableBalance.selector),
            abi.encode(userAvailableBalance)
        );

        vm.mockCall(
            address(lendingPool),
            abi.encodeWithSelector(ILendingPool.getPendingPool.selector),
            abi.encode(address(0x11ff))
        );

        address pendingPool = ILendingPool(lendingPool).getPendingPool();

        vm.mockCall(
            address(pendingPool), abi.encodeWithSelector(IPendingPool.getUserPendingAmounts.selector), abi.encode(0, 0)
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
