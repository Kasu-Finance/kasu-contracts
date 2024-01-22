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

contract LendingPoolManagerTest is Test {
    LendingPoolManager internal lendingPoolManager;
    LendingPoolDeployment internal lendingPoolDeployment;
    MockERC20Permit mockUsdc;

    address internal admin = address(0xad);
    address internal alice = address(0xaaa);

    function setUp() public {
        // proxy admin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

        // usdc
        mockUsdc = new MockERC20Permit("USDC", "USDC", 6);

        // lending pool manager
        LendingPoolManager lendingPoolManagerImpl = new LendingPoolManager(address(mockUsdc));
        TransparentUpgradeableProxy lendingPoolManagerProxy =
            new TransparentUpgradeableProxy(address(lendingPoolManagerImpl), address(proxyAdmin), "");
        lendingPoolManager = LendingPoolManager(address(lendingPoolManagerProxy));

        // lending pool
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration = PoolConfiguration(
            "Test Lending Pool", "TLP", address(mockUsdc), minDepositAmount, targetExcessLiquidity, tranches
        );

        PendingPool pendingPoolIml = new PendingPool(address(mockUsdc), lendingPoolManager);
        UpgradeableBeacon pendingPoolBeacon = new UpgradeableBeacon(address(pendingPoolIml), admin);

        LendingPool lendingPoolImp = new LendingPool();
        UpgradeableBeacon lendingPoolBeacon = new UpgradeableBeacon(address(lendingPoolImp), admin);

        LendingPoolTranche lendingPoolTrancheImp = new LendingPoolTranche(lendingPoolManager);
        UpgradeableBeacon lendingPoolTrancheBeacon = new UpgradeableBeacon(address(lendingPoolTrancheImp), admin);

        LendingPoolFactory lendingPoolFactory = new LendingPoolFactory(
            address(pendingPoolBeacon), address(lendingPoolBeacon), address(lendingPoolTrancheBeacon)
        );

        startHoax(admin);
        lendingPoolDeployment = lendingPoolFactory.createPool(poolConfiguration, lendingPoolManager);
    }

    function test_when_alice_requests_deposit_then_funds_move_to_pending_pool() public {
        // act
        uint256 requestDepositAmount = 100 * 1e6;
        deal(address(mockUsdc), alice, requestDepositAmount, true);
        vm.startPrank(alice);
        mockUsdc.approve(address(lendingPoolManager), requestDepositAmount);
        uint256 dNftId = lendingPoolManager.requestDeposit(
            lendingPoolDeployment.lendingPool, lendingPoolDeployment.tranches[0], requestDepositAmount
        );
        vm.stopPrank();

        // assert
        assertApproxEqAbs(mockUsdc.balanceOf(alice), 0, 0);
        assertApproxEqAbs(mockUsdc.balanceOf(address(lendingPoolDeployment.pendingPool)), requestDepositAmount, 0);

        PendingPool pendingPool = PendingPool(lendingPoolDeployment.pendingPool);
        assertEq(pendingPool.ownerOf(dNftId), alice);

        DepositNftDetails memory depositNftDetails = pendingPool.trancheDepositNftDetails(dNftId);
        assertEq(depositNftDetails.assetAmount, requestDepositAmount);
        // TODO: assert epochId, priorityLevel
    }
}
