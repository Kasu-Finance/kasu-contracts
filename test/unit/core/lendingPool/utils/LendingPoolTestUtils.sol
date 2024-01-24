// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/Test.sol";
import "../../../../shared/MockUSDC.sol";
import "../../../../../src/core/lendingPool/LendingPoolManager.sol";
import "../../../../../src/core/lendingPool/LendingPoolFactory.sol";
import {BaseTestUtils} from "../../../../shared/BaseTestUtils.sol";

contract LendingPoolTestUtils is BaseTestUtils {
    LendingPoolManager internal lendingPoolManager;
    MockUSDC internal mockUsdc;

    LendingPoolFactory private lendingPoolFactory;

    function __lendingPool_setUp() internal {
        // fund accounts
        vm.deal(admin, 1 << 128);
        vm.deal(alice, 1 << 128);
        vm.deal(bob, 1 << 128);
        // proxy admin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        // usdc
        MockUSDC mockUsdcIml = new MockUSDC();
        TransparentUpgradeableProxy mockUsdcProxy =
            new TransparentUpgradeableProxy(address(mockUsdcIml), address(proxyAdmin), "");
        mockUsdc = MockUSDC(address(mockUsdcProxy));
        mockUsdc.initialize(admin);
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
        vm.prank(admin);
        lendingPoolDeployment = lendingPoolFactory.createPool(poolConfiguration, lendingPoolManager);
        // fund lending pool
        vm.deal(lendingPoolDeployment.lendingPool, 1 << 128);
    }

    // ###  Helper Functions ###

    function _requestDeposit(address sender, address lendingPool, address tranche, uint256 amount)
        internal
        prank(sender)
        returns (uint256 dNftId)
    {
        deal(address(mockUsdc), sender, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        return lendingPoolManager.requestDeposit(lendingPool, tranche, amount);
    }

    function _acceptDeposit(address pendingPool, address lendingPool, address tranche, uint256 amount)
        internal
        prank(pendingPool)
    {
        mockUsdc.approve(address(lendingPool), amount);
        ILendingPool(lendingPool).acceptDeposit(tranche, alice, amount);
    }
}
