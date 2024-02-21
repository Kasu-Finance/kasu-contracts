// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ILendingPoolFactory,
    PoolConfiguration,
    LendingPoolDeployment
} from "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../lendingPool/LendingPoolHelpers.sol";
import "./LendingPool.sol";
import {LendingPoolManager} from "./LendingPoolManager.sol";
import {ILendingPoolManager} from "../interfaces/lendingPool/ILendingPoolManager.sol";
import {IKasuController} from "../../shared/interfaces/IKasuController.sol";
import "../../shared/access/Roles.sol";
import {PendingPool} from "./PendingPool.sol";
import {LendingPoolTranche} from "./LendingPoolTranche.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import "forge-std/console2.sol";

contract LendingPoolFactory is ILendingPoolFactory, LendingPoolHelpers {
    address private immutable pendingPoolBeacon;
    address private immutable lendingPoolBeacon;
    address private immutable lendingPoolTrancheBeacon;
    IKasuController private immutable kasuController;

    constructor(
        address pendingPoolBeacon_,
        address lendingPoolBeacon_,
        address lendingPoolTrancheBeacon_,
        IKasuController kasuController_,
        ILendingPoolManager lendingPoolManager_
    ) LendingPoolHelpers(lendingPoolManager_) {
        pendingPoolBeacon = pendingPoolBeacon_;
        lendingPoolBeacon = lendingPoolBeacon_;
        lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
        kasuController = kasuController_;
    }

    function createPool(PoolConfiguration calldata poolConfiguration)
        external
        onlyLendingPoolManager
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // lending pool deploy
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));

        if (poolConfiguration.tranches.length == 0) {
            revert("LendingPoolFactory: at least senior tranche must be enabled");
        }

        // tranches deploy
        lendingPoolDeployment.lendingPool = address(lendingPoolBeaconProxy);
        lendingPoolDeployment.tranches = new address[](poolConfiguration.tranches.length);

        address[] memory trancheAddresses = new address[](poolConfiguration.tranches.length);

        address trancheAddress;
        for (uint256 i; i < poolConfiguration.tranches.length; ++i) {
            trancheAddresses[i] = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Senior Tranche", "sr", lendingPool
            );
            lendingPoolDeployment.tranches[i] = trancheAddresses[i];
        }

        // pending pool deploy
        BeaconProxy pendingPoolBeaconProxy = new BeaconProxy(pendingPoolBeacon, "");
        PendingPool pendingPool = PendingPool(address(pendingPoolBeaconProxy));
        pendingPool.initialize("Pending pool nft", "PP", lendingPool);
        address pendingPoolAddress = address(pendingPool);

        lendingPoolDeployment.pendingPool = pendingPoolAddress;

        LendingPoolInfo memory lendingPoolInfo;
        lendingPoolInfo.pendingPoolAddress = pendingPoolAddress;
        lendingPoolInfo.trancheAddresses = trancheAddresses;

        lendingPool.initialize(poolConfiguration, lendingPoolInfo, address(lendingPoolManager));

        pendingPool.setUpTranches();

        // access control
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_LENDING_POOL_ADMIN, poolConfiguration.poolAdmin
        );

        emit PoolCreated(lendingPoolDeployment.lendingPool, lendingPoolDeployment);
    }

    function _deployLendingPoolTranche(
        string memory poolName,
        string memory poolSymbol,
        string memory trancheName,
        string memory trancheSymbol,
        ILendingPool lendingPool
    ) internal returns (address) {
        BeaconProxy lendingPoolTrancheBeaconProxy = new BeaconProxy(lendingPoolTrancheBeacon, "");
        LendingPoolTranche lendingPoolTranche = LendingPoolTranche(address(lendingPoolTrancheBeaconProxy));

        string memory fullTrancheName = string.concat(poolName, " - ", trancheName);
        string memory fullTrancheSymbol = string.concat(trancheSymbol, "_", poolSymbol);

        lendingPoolTranche.initialize(fullTrancheName, fullTrancheSymbol, lendingPool);

        return address(lendingPoolTranche);
    }
}
