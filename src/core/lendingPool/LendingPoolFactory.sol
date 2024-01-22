// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    ILendingPoolFactory,
    PoolConfiguration,
    LendingPoolDeployment
} from "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "./LendingPool.sol";
import {LendingPoolManager} from "./LendingPoolManager.sol";
import {ILendingPoolManager} from "../interfaces/lendingPool/ILendingPoolManager.sol";
import {PendingPool} from "./PendingPool.sol";
import {LendingPoolTranche} from "./LendingPoolTranche.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "forge-std/console2.sol";

contract LendingPoolFactory is ILendingPoolFactory {
    address private immutable pendingPoolBeacon;
    address private immutable lendingPoolBeacon;
    address private immutable lendingPoolTrancheBeacon;

    constructor(address pendingPoolBeacon_, address lendingPoolBeacon_, address lendingPoolTrancheBeacon_) {
        pendingPoolBeacon = pendingPoolBeacon_;
        lendingPoolBeacon = lendingPoolBeacon_;
        lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
    }

    function createPool(PoolConfiguration calldata poolConfiguration, ILendingPoolManager lendingPoolManager)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // lending pool deploy
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));
        address lendingPoolAddress = address(lendingPoolBeaconProxy);

        // tranches deploy
        address[] memory tranches = new address[](3);
        if (poolConfiguration.tranches.junior.isEnabled) {
            address juniorTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Junior Tranche", "jr", lendingPool
            );
            tranches[0] = juniorTranche;
        }
        if (poolConfiguration.tranches.mezzo.isEnabled) {
            address mezzoTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Mezzo Tranche", "mz", lendingPool
            );
            tranches[1] = mezzoTranche;
        }
        if (poolConfiguration.tranches.senior.isEnabled) {
            address seniorTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Senior Tranche", "sr", lendingPool
            );
            tranches[2] = seniorTranche;
        }
        // pending pool deploy
        address pendingPoolAddress = _deployPendingPool(lendingPool, tranches);

        LendingPoolInfo memory lendingPoolInfo;
        lendingPoolInfo.pendingPool = pendingPoolAddress;

        lendingPool.initialize(poolConfiguration.name, poolConfiguration.symbol, lendingPoolInfo);

        lendingPoolDeployment.lendingPool = lendingPoolAddress;
        lendingPoolDeployment.pendingPool = pendingPoolAddress;
        lendingPoolDeployment.tranches = tranches;

        lendingPoolManager.registerLendingPool(lendingPoolDeployment);
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
        string memory fullTrancheSymbol = string.concat(poolSymbol, "_", trancheSymbol);

        lendingPoolTranche.initialize(fullTrancheName, fullTrancheSymbol, lendingPool);

        return address(lendingPoolTranche);
    }

    function _deployPendingPool(ILendingPool lendingPool, address[] memory tranches) internal returns (address) {
        BeaconProxy pendingPoolBeaconProxy = new BeaconProxy(pendingPoolBeacon, "");
        PendingPool pendingPool = PendingPool(address(pendingPoolBeaconProxy));

        // TODO: update pending NFT name and symbol
        pendingPool.initialize("Pending pool nft", "PP", lendingPool, tranches);

        return address(pendingPool);
    }
}
