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
import {IKasuController} from "../../shared/interfaces/IKasuController.sol";
import "../../shared/access/Roles.sol";
import {PendingPool} from "./PendingPool.sol";
import {LendingPoolTranche} from "./LendingPoolTranche.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "forge-std/console2.sol";

contract LendingPoolFactory is ILendingPoolFactory {
    address private immutable pendingPoolBeacon;
    address private immutable lendingPoolBeacon;
    address private immutable lendingPoolTrancheBeacon;
    IKasuController private immutable kasuController;

    constructor(
        address pendingPoolBeacon_,
        address lendingPoolBeacon_,
        address lendingPoolTrancheBeacon_,
        IKasuController kasuController_
    ) {
        pendingPoolBeacon = pendingPoolBeacon_;
        lendingPoolBeacon = lendingPoolBeacon_;
        lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
        kasuController = kasuController_;
    }

    function createPool(PoolConfiguration calldata poolConfiguration, ILendingPoolManager lendingPoolManager)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // lending pool deploy
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));

        uint256 trancheCount;
        if (poolConfiguration.tranches.junior.isEnabled) {
            trancheCount++;
        }

        if (poolConfiguration.tranches.mezzo.isEnabled) {
            trancheCount++;
        }

        if (poolConfiguration.tranches.senior.isEnabled) {
            trancheCount++;
        }

        if (trancheCount == 0) {
            revert("LendingPoolFactory: at least senior tranche must be enabled");
        }

        // tranches deploy
        TrancheData[] memory tranches = new TrancheData[](trancheCount);
        if (poolConfiguration.tranches.junior.isEnabled) {
            if (trancheCount < 2) {
                revert("LendingPoolFactory: junior tranche cannot be enabled without senior tranche");
            }

            address juniorTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Junior Tranche", "jr", lendingPool
            );
            tranches[0] = TrancheData(
                juniorTranche, poolConfiguration.tranches.junior.ratio, poolConfiguration.tranches.junior.interestRate
            );
        }
        if (poolConfiguration.tranches.mezzo.isEnabled) {
            if (trancheCount < 3) {
                revert("LendingPoolFactory: mezzo tranche cannot be enabled without senior and junior tranche");
            }

            address mezzoTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Mezzo Tranche", "mz", lendingPool
            );
            tranches[1] = TrancheData(
                mezzoTranche, poolConfiguration.tranches.mezzo.ratio, poolConfiguration.tranches.mezzo.interestRate
            );
        }
        if (poolConfiguration.tranches.senior.isEnabled) {
            address seniorTranche = _deployLendingPoolTranche(
                poolConfiguration.name, poolConfiguration.symbol, "Senior Tranche", "sr", lendingPool
            );
            tranches[trancheCount - 1] = TrancheData(
                seniorTranche, poolConfiguration.tranches.senior.ratio, poolConfiguration.tranches.senior.interestRate
            );
        }

        lendingPoolDeployment.lendingPool = address(lendingPoolBeaconProxy);
        lendingPoolDeployment.tranches = new address[](trancheCount);
        for (uint256 i; i < tranches.length; i++) {
            lendingPoolDeployment.tranches[i] = tranches[i].trancheAddress;
        }

        // pending pool deploy
        address pendingPoolAddress = _deployPendingPool(lendingPool, lendingPoolDeployment.tranches);

        lendingPoolDeployment.pendingPool = pendingPoolAddress;

        LendingPoolInfo memory lendingPoolInfo;
        lendingPoolInfo.pendingPool = pendingPoolAddress;
        lendingPoolInfo.tranches = tranches;

        lendingPool.initialize(
            poolConfiguration.name, poolConfiguration.symbol, lendingPoolInfo, msg.sender, address(lendingPoolManager)
        );

        lendingPoolManager.registerLendingPool(lendingPoolDeployment);

        // access control
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_LENDING_POOL_ADMIN, poolConfiguration.poolAdmin
        );
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

    function _deployPendingPool(ILendingPool lendingPool, address[] memory tranches) internal returns (address) {
        BeaconProxy pendingPoolBeaconProxy = new BeaconProxy(pendingPoolBeacon, "");
        PendingPool pendingPool = PendingPool(address(pendingPoolBeaconProxy));

        // TODO: update pending NFT name and symbol
        pendingPool.initialize("Pending pool nft", "PP", lendingPool, tranches);

        return address(pendingPool);
    }
}
