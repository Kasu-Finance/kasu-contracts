// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import {LendingPoolFactory} from "../../../src/core/lendingPool/LendingPoolFactory.sol";
import "../../../src/core/lendingPool/LendingPoolManager.sol";
import "../../../src/core/lendingPool/PendingPool.sol";
import "../../../src/core/lendingPool/LendingPool.sol";
import "../../../src/core/lendingPool/LendingPoolTranche.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/Test.sol";
import "../../shared/MockERC20Permit.sol";

contract LendingPoolTestUtils is Test {
    LendingPoolManager internal lendingPoolManager;
    MockERC20Permit internal mockUsdc;

    LendingPoolFactory private lendingPoolFactory;

    address internal admin = address(0xad);
    address internal alice = address(0xaaa);

    function __lendingPool_setUp() internal {
        // proxy admin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        // usdc
        MockERC20Permit mockUsdcIml = new MockERC20Permit("USDC", "USDC", 6);
        TransparentUpgradeableProxy mockUsdcProxy =
                    new TransparentUpgradeableProxy(address(mockUsdcIml), address(proxyAdmin), "");
        mockUsdc = MockERC20Permit(address(mockUsdcProxy));
        // lending pool manager
        LendingPoolManager lendingPoolManagerImpl = new LendingPoolManager(address(mockUsdc));
        TransparentUpgradeableProxy lendingPoolManagerProxy =
            new TransparentUpgradeableProxy(address(lendingPoolManagerImpl), address(proxyAdmin), "");
        lendingPoolManager = LendingPoolManager(address(lendingPoolManagerProxy));
        // pending pool
        PendingPool pendingPoolIml = new PendingPool(address(mockUsdc), lendingPoolManager);
        UpgradeableBeacon pendingPoolBeacon = new UpgradeableBeacon(address(pendingPoolIml), admin);
        // lending pool
        LendingPool lendingPoolImp = new LendingPool(address(mockUsdc));
        UpgradeableBeacon lendingPoolBeacon = new UpgradeableBeacon(address(lendingPoolImp), admin);
        // lending pool tranche
        LendingPoolTranche lendingPoolTrancheImp = new LendingPoolTranche(lendingPoolManager);
        UpgradeableBeacon lendingPoolTrancheBeacon = new UpgradeableBeacon(address(lendingPoolTrancheImp), admin);
        // lending pool factory
        LendingPoolFactory lendingPoolFactoryImpl = new LendingPoolFactory(
            address(pendingPoolBeacon), address(lendingPoolBeacon), address(lendingPoolTrancheBeacon)
        );
        TransparentUpgradeableProxy lendingPoolFactoryProxy =
                    new TransparentUpgradeableProxy(address(lendingPoolFactoryImpl), address(proxyAdmin), "");
        lendingPoolFactory = LendingPoolFactory(address(lendingPoolFactoryProxy));
    }

    function createLendingPool(PoolConfiguration memory poolConfiguration)
        internal
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        startHoax(admin);
        lendingPoolDeployment = lendingPoolFactory.createPool(poolConfiguration, lendingPoolManager);
    }
}
