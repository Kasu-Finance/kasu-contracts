// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../_utils/LockingTestUtils.sol";
import {UserManager} from "../../../src/core/UserManager.sol";
import "../../../src/core/interfaces/IUserManager.sol";
import "../../../src/core/interfaces/IUserLoyaltyRewards.sol";
import "../../../src/core/SystemVariables.sol";
import "../../shared/MockKsuPrice.sol";

contract UserManagerTest is LockingTestUtils {
    IUserManager private userManager;
    ISystemVariables private systemVariables;

    function setUp() public {
        __baseTestUtils_setUp();
        __locking_setUp();

        MockKsuPrice ksuPrice = new MockKsuPrice();

        SystemVariables systemVariablesImpl = new SystemVariables(ksuPrice, _kasuController);
        TransparentUpgradeableProxy systemVariablesProxy =
            new TransparentUpgradeableProxy(address(systemVariablesImpl), address(proxyAdmin), "");
        systemVariables = ISystemVariables(address(systemVariablesProxy));

        IUserLoyaltyRewards userLoyaltyRewards = IUserLoyaltyRewards(address(0x9999));

        UserManager userManagerImpl = new UserManager(systemVariables, _KSULocking, userLoyaltyRewards);
        TransparentUpgradeableProxy userManagerProxy =
            new TransparentUpgradeableProxy(address(userManagerImpl), address(proxyAdmin), "");
        userManager = IUserManager(address(userManagerProxy));
    }

    function test_canUserDepositInJuniorTranche_whenUserHasRKsuLockedAndFlagIsFalse() public {
        // ARRANGE
        _lock(alice, 50 ether, lockPeriod30);
        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(false);

        // ACT
        bool canAliceDepositInJuniorTranche = userManager.canUserDepositInJuniorTranche(alice);

        // ASSERT
        assertTrue(canAliceDepositInJuniorTranche);
    }

    function test_canUserDepositInJuniorTranche_whenUserHasRKsuLockedAndFlagIsTrue() public {
        // ARRANGE
        _lock(alice, 50 ether, lockPeriod30);
        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(true);

        // ACT
        bool canAliceDepositInJuniorTranche = userManager.canUserDepositInJuniorTranche(alice);

        // ASSERT
        assertTrue(canAliceDepositInJuniorTranche);
    }

    function test_canUserDepositInJuniorTranche_whenUserHasNoRKsuLockedAndFlagIsFalse() public {
        // ARRANGE
        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(false);

        // ACT
        bool canAliceDepositInJuniorTranche = userManager.canUserDepositInJuniorTranche(alice);

        // ASSERT
        assertTrue(canAliceDepositInJuniorTranche);
    }

    function test_canUserDepositInJuniorTranche_whenUserHasNoRKsuLockedAndFlagIsTrue() public {
        // ARRANGE
        vm.prank(admin);
        systemVariables.setUserCanDepositToJuniorTrancheWhenHeHasRKSU(true);

        // ACT
        bool canAliceDepositInJuniorTranche = userManager.canUserDepositInJuniorTranche(alice);

        // ASSERT
        assertFalse(canAliceDepositInJuniorTranche);
    }
}
