// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../_utils/BaseTestUtils.sol";
import "../_utils/LockingTestUtils.sol";
import "../../../src/core/UserManager.sol";
import "../../../src/core/UserLoyaltyRewards.sol";
import "../../../src/core/interfaces/ISystemVariables.sol";
import "../../../src/core/interfaces/IUserLoyaltyRewards.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPool.sol";
import "../../../src/locking/interfaces/IKSULocking.sol";
import "../../shared/ManualKsuPrice.sol";

// ========================================================================
// H-01: UserManager stale _isUserPartOfLendingPool mapping
// ========================================================================

contract H01_StalePoolMappingTest is BaseTestUtils {
    ISystemVariables internal systemVariables;
    IKSULocking internal ksuLocking;
    UserManager internal userManager;
    IUserLoyaltyRewards internal userLoyaltyRewards;
    address internal lendingPoolManager;

    address lendingPool1 = address(0x1111);
    address pendingPool1 = address(0x11ff);

    function setUp() public {
        ksuLocking = IKSULocking(address(0xeeee));
        systemVariables = ISystemVariables(address(0xffff));
        lendingPoolManager = address(0x1234);
        userLoyaltyRewards = IUserLoyaltyRewards(address(0x9999));

        UserManager userManagerImpl = new UserManager(systemVariables, ksuLocking, userLoyaltyRewards);
        TransparentUpgradeableProxy userManagerProxy =
            new TransparentUpgradeableProxy(address(userManagerImpl), address(proxyAdmin), "");
        userManager = UserManager(address(userManagerProxy));

        userManager.initialize(lendingPoolManager);

        vm.mockCall(address(ksuLocking), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        _mockDefaultLendingPool(lendingPool1, pendingPool1);

        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.currentEpochNumber.selector),
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
        vm.mockCall(address(ksuLocking), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
    }

    /**
     * @notice H-01 FIX: After cleanup, re-depositing into the same pool re-adds it
     * to _userLendingPools because _isUserPartOfLendingPool is now reset to false.
     */
    function test_H01_reDepositAfterCleanup_poolMustBeReTracked() public {
        // 1. Alice deposits into pool1
        _userRequestedDeposit(alice, lendingPool1);
        address[] memory alicePools = userManager.userLendingPools(alice);
        assertEq(alicePools.length, 1, "Alice should have 1 pool");

        // 2. Admin removes alice (she has zero balance - mocked default)
        userManager.updateUserLendingPools(0, 0);
        alicePools = userManager.userLendingPools(alice);
        assertEq(alicePools.length, 0, "Alice should have 0 pools after cleanup");

        // 3. Alice re-deposits into the same pool
        _userRequestedDeposit(alice, lendingPool1);

        // 4. Pool MUST be re-tracked (fix: _isUserPartOfLendingPool reset in _removeLendingPoolFromUser)
        alicePools = userManager.userLendingPools(alice);
        assertEq(alicePools.length, 1, "H-01: Pool must be re-tracked after re-deposit");
        assertEq(alicePools[0], lendingPool1, "H-01: Pool address must match");
    }

    /**
     * @notice H-01 FIX: Loyalty level is correct after re-deposit.
     */
    function test_H01_loyaltyLevelCorrectAfterReDeposit() public {
        uint256[] memory loyaltyThresholds = new uint256[](2);
        loyaltyThresholds[0] = 1_00;
        loyaltyThresholds[1] = 3_00;
        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.loyaltyThresholds.selector),
            abi.encode(loyaltyThresholds)
        );
        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.ksuEpochTokenPrice.selector),
            abi.encode(2e18)
        );
        // M-04: _loyaltyParameters now reads ksuEpochTokenPriceFresh (view-safe fallback)
        vm.mockCall(
            address(systemVariables),
            abi.encodeWithSelector(ISystemVariables.ksuEpochTokenPriceFresh.selector),
            abi.encode(2e18)
        );

        // 1. Alice deposits, then gets cleaned up
        _userRequestedDeposit(alice, lendingPool1);
        userManager.updateUserLendingPools(0, 0);

        // 2. Alice re-deposits with a real balance
        _userRequestedDeposit(alice, lendingPool1);

        // Mock alice having 1000 USDC in the pool and 5 rKSU
        vm.mockCall(
            address(lendingPool1),
            abi.encodeCall(ILendingPool.userBalance, (alice)),
            abi.encode(1000 * 1e6)
        );
        vm.mockCall(
            address(ksuLocking),
            abi.encodeWithSelector(IERC20.balanceOf.selector, alice),
            abi.encode(5 * 1e18)
        );

        // 3. Loyalty level should be 1 (1% ratio) — fix ensures pool is tracked
        (, uint256 loyaltyLevel) = userManager.userLoyaltyLevel(alice);
        assertEq(loyaltyLevel, 1, "H-01: Loyalty level should be 1, not max");
    }

    function _userRequestedDeposit(address user, address lendingPool) internal prank(lendingPoolManager) {
        userManager.userRequestedDeposit(user, lendingPool);
    }

    function _mockDefaultLendingPool(address lendingPool, address pendingPool) internal {
        vm.mockCall(
            address(lendingPool), abi.encodeWithSelector(ILendingPool.userBalance.selector), abi.encode(uint256(0))
        );
        vm.mockCall(
            address(lendingPool), abi.encodeWithSelector(ILendingPool.pendingPool.selector), abi.encode(pendingPool)
        );
        vm.mockCall(
            address(pendingPool),
            abi.encodeWithSelector(IPendingPool.userPendingDepositAmount.selector),
            abi.encode(uint256(0))
        );
    }
}

// ========================================================================
// M-01: Fee loss when no eligible rKSU holders — now reverts
// ========================================================================

contract M01_FeeLossNoEligibleHoldersTest is LockingTestUtils {
    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();
    }

    /**
     * @notice M-01 FIX: emitFees now reverts when eligibleRKSUForFees == 0.
     */
    function test_M01_emitFeesRevertsWhenNoEligibleHolders() public {
        uint256 feeAmount = 1000 * 1e6;

        deal(address(mockUsdc), admin, feeAmount, true);
        vm.startPrank(admin);
        mockUsdc.approve(address(_KSULocking), feeAmount);
        vm.expectRevert(abi.encodeWithSelector(IKSULocking.NoEligibleFeeRecipients.selector));
        _KSULocking.emitFees(feeAmount);
        vm.stopPrank();
    }

    /**
     * @notice M-01: emitFees should still work normally when there ARE eligible holders.
     */
    function test_M01_emitFeesSucceedsWithEligibleHolders() public {
        _lock(alice, 50 ether, lockPeriod30);

        vm.prank(admin);
        _KSULocking.setCanSetFeeRecipient(admin, true);
        vm.prank(admin);
        _KSULocking.enableFeesForUser(alice);

        _emitFees(1000 * 1e6);

        vm.prank(alice);
        uint256 claimed = _KSULocking.claimFees();
        assertGt(claimed, 0, "Alice should have claimable fees");
    }
}

// ========================================================================
// M-02: recoverERC20 removed from UserLoyaltyRewards
// ========================================================================

contract M02_RecoverERC20RemovedTest is LockingTestUtils {
    IUserLoyaltyRewards internal _userLoyaltyRewards;

    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();

        ManualKsuPrice ksuPrice = new ManualKsuPrice();

        UserLoyaltyRewards userLoyaltyRewardsImpl = new UserLoyaltyRewards(ksuPrice, _ksu, _kasuController);
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(userLoyaltyRewardsImpl), address(proxyAdmin), "");
        _userLoyaltyRewards = UserLoyaltyRewards(address(proxy));
    }

    /**
     * @notice M-02 FIX: recoverERC20 no longer exists.
     */
    function test_M02_recoverERC20DoesNotExist() public {
        bytes memory callData = abi.encodeWithSignature(
            "recoverERC20(address,uint256,address)",
            address(_ksu),
            100 * 1e18,
            admin
        );
        vm.prank(admin);
        (bool success,) = address(_userLoyaltyRewards).call(callData);
        assertFalse(success, "M-02: recoverERC20 should not exist");
    }
}
