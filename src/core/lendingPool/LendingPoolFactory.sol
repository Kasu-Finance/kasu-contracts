// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../../shared/interfaces/IKasuController.sol";
import "../../shared/access/Roles.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../lendingPool/LendingPoolHelpers.sol";
import "./LendingPool.sol";
import "./LendingPoolManager.sol";
import "./PendingPool.sol";
import "./LendingPoolTranche.sol";
import "../SystemVariables.sol";

contract LendingPoolFactory is ILendingPoolFactory, LendingPoolHelpers {
    address private immutable pendingPoolBeacon;
    address private immutable lendingPoolBeacon;
    address private immutable lendingPoolTrancheBeacon;
    IKasuController private immutable kasuController;
    ISystemVariables private immutable systemVariables;

    constructor(
        address pendingPoolBeacon_,
        address lendingPoolBeacon_,
        address lendingPoolTrancheBeacon_,
        IKasuController kasuController_,
        ILendingPoolManager lendingPoolManager_,
        ISystemVariables systemVariables_
    ) LendingPoolHelpers(lendingPoolManager_) {
        pendingPoolBeacon = pendingPoolBeacon_;
        lendingPoolBeacon = lendingPoolBeacon_;
        lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
        kasuController = kasuController_;
        systemVariables = systemVariables_;
    }

    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        onlyLendingPoolManager
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // lending pool deploy
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));

        // tranches deploy
        uint256 trancheCount = createPoolConfig.tranches.length;
        lendingPoolDeployment.lendingPool = address(lendingPoolBeaconProxy);
        lendingPoolDeployment.tranches = new address[](trancheCount);

        address[] memory trancheAddresses = new address[](trancheCount);

        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            trancheAddresses[i] = _deployLendingPoolTranche(
                createPoolConfig.poolName, createPoolConfig.poolSymbol, i, trancheCount, lendingPool
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

        PoolConfiguration memory poolConfiguration =
            lendingPool.initialize(createPoolConfig, lendingPoolInfo, address(lendingPoolManager));

        pendingPool.setUpTranches();

        // access control
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_LENDING_POOL_ADMIN, createPoolConfig.poolAdmin
        );

        emit PoolCreated(lendingPoolDeployment.lendingPool, lendingPoolDeployment, poolConfiguration);
    }

    function _deployLendingPoolTranche(
        string memory poolName,
        string memory poolSymbol,
        uint256 trancheIndex,
        uint256 trancheCount,
        ILendingPool lendingPool
    ) internal returns (address) {
        BeaconProxy lendingPoolTrancheBeaconProxy = new BeaconProxy(lendingPoolTrancheBeacon, "");
        LendingPoolTranche lendingPoolTranche = LendingPoolTranche(address(lendingPoolTrancheBeaconProxy));

        (string memory fullTrancheName, string memory fullTrancheSymbol) =
            getTrancheName(poolName, poolSymbol, trancheIndex, trancheCount);

        lendingPoolTranche.initialize(fullTrancheName, fullTrancheSymbol, lendingPool);

        return address(lendingPoolTranche);
    }

    function getTrancheName(
        string memory lendingPoolName,
        string memory lendingPoolSymbol,
        uint256 trancheIndex,
        uint256 trancheCount
    ) internal view returns (string memory, string memory) {
        if (trancheCount < systemVariables.minTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count less than minimum");
        }

        if (trancheCount > systemVariables.maxTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count more than maximum");
        }

        uint256 trancheNameIndex = trancheIndex;
        if (trancheCount == 2) trancheNameIndex = trancheIndex + 1;
        if (trancheCount == 3) trancheNameIndex = trancheIndex + 2;

        if (trancheIndex > 3) {
            revert InvalidConfiguration();
        }

        TrancheInfo memory trancheInfo = systemVariables.getTrancheInfo(trancheIndex);

        return (
            string.concat(lendingPoolName, " - ", trancheInfo.trancheName),
            string.concat(trancheInfo.tokenSymbol, "_", lendingPoolSymbol)
        );
    }
}
