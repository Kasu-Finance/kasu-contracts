// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ILendingPoolFactory,
    PoolConfiguration,
    LendingPoolDeployment
} from "../interfaces/lendingPool/ILendingPoolFactory.sol";
import {LendingPool} from "./LendingPool.sol";
import {LendingPoolManager} from "./LendingPoolManager.sol";
import {PendingPool} from "./PendingPool.sol";
import {LendingPoolTranche} from "./LendingPoolTranche.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract LendingPoolFactory is ILendingPoolFactory {
    address private immutable pendingPoolBeacon;
    address private immutable lendingPoolBeacon;
    address private immutable lendingPoolManagerBeacon;
    address private immutable lendingPoolTrancheBeacon;

    constructor(
        address pendingPoolBeacon_,
        address lendingPoolBeacon_,
        address lendingPoolManagerBeacon_,
        address lendingPoolTrancheBeacon_
    ) {
        pendingPoolBeacon = pendingPoolBeacon_;
        lendingPoolBeacon = lendingPoolBeacon_;
        lendingPoolManagerBeacon = lendingPoolManagerBeacon_;
        lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
    }

    function createPool(PoolConfiguration calldata poolConfiguration)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        address lendingPoolManagerAddress = _deployLendingPoolManager();
        address lendingPoolAddress = _deployLendingPool();

        address[] memory tranches = new address[](3);
        if (poolConfiguration.tranches.junior.isEnabled) {
            address juniorTranche =
                _deployLendingPoolTranche(proxyAdmin, "Junior Tranche Token", "JTT", lendingPoolAddress);
            tranches[0] = juniorTranche;
        }
        if (poolConfiguration.tranches.mezzo.isEnabled) {
            address mezzoTranche =
                _deployLendingPoolTranche(proxyAdmin, "Mezzo Tranche Token", "MTT", lendingPoolAddress);
            tranches[1] = mezzoTranche;
        }
        if (poolConfiguration.tranches.senior.isEnabled) {
            address seniorTranche =
                _deployLendingPoolTranche(proxyAdmin, "Senior Tranche Token", "STT", lendingPoolAddress);
            tranches[2] = seniorTranche;
        }

        address pendingPoolAddress = _deployPendingPool(tranches);

        lendingPoolDeployment.lendingPoolManager = lendingPoolManagerAddress;
        lendingPoolDeployment.lendingPool = lendingPoolAddress;
        lendingPoolDeployment.pendingPool = pendingPoolAddress;
        lendingPoolDeployment.tranches = tranches;

        LendingPoolManager lendingPoolManager = LendingPoolManager(lendingPoolManagerAddress);
        lendingPoolManager.registerLendingPool(lendingPoolDeployment);
    }

    function _deployLendingPoolManager() internal returns (address) {
        BeaconProxy lendingPoolManagerBeaconProxy = new BeaconProxy(lendingPoolManagerBeacon, "");
        LendingPoolManager lendingPoolManager = LendingPoolManager(address(lendingPoolManagerBeaconProxy));

        return address(lendingPoolManager);
    }

    function _deployLendingPool() internal returns (address) {
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));
        lendingPool.initialize("Lending pool token", "LP");

        return address(lendingPool);
    }

    function _deployLendingPoolTranche(
        ProxyAdmin proxyAdmin,
        string memory name,
        string memory symbol,
        address lendingPoolAddress
    ) internal returns (address) {
        BeaconProxy lendingPoolTrancheBeaconProxy = new BeaconProxy(lendingPoolTrancheBeacon, "");
        LendingPoolTranche lendingPoolTranche = LendingPoolTranche(address(lendingPoolTrancheBeaconProxy));
        IERC20 lpToken = IERC20(lendingPoolAddress);
        lendingPoolTranche.initialize(name, symbol, lpToken, lendingPoolAddress);

        return address(lendingPoolTranche);
    }

    function _deployPendingPool(address[] memory tranches) internal returns (address) {
        BeaconProxy pendingPoolBeaconProxy = new BeaconProxy(pendingPoolBeacon, "");
        PendingPool pendingPool = PendingPool(address(pendingPoolBeaconProxy));

        pendingPool.initialize("Pending pool token", "PP", tranches);

        return address(pendingPool);
    }
}
