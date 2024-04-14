// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../../shared/interfaces/IKasuController.sol";
import "../../shared/access/Roles.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "./LendingPool.sol";
import "./LendingPoolManager.sol";
import "./PendingPool.sol";
import "./LendingPoolTranche.sol";
import "../SystemVariables.sol";
import "../../shared/AddressLib.sol";

/**
 * @title LendingPoolFactory contract
 * @notice Factory contract for creating lending pools.
 */
contract LendingPoolFactory is ILendingPoolFactory {
    /// @notice Pending pool beacon address.
    address private immutable _pendingPoolBeacon;
    /// @notice Lending pool beacon address.
    address private immutable _lendingPoolBeacon;
    /// @notice Lending pool tranche beacon address.
    address private immutable _lendingPoolTrancheBeacon;
    /// @notice Kasu controller contract.
    IKasuController private immutable _kasuController;
    /// @notice Lending pool manager contract.
    address private immutable _lendingPoolManager;
    /// @notice System variables contract.
    ISystemVariables private immutable _systemVariables;

    /**
     * @notice Constructor.
     * @param pendingPoolBeacon_ Pending pool beacon address.
     * @param lendingPoolBeacon_ Lending pool beacon address.
     * @param lendingPoolTrancheBeacon_ Lending pool tranche beacon address.
     * @param kasuController_ Kasu controller contract.
     * @param lendingPoolManager_ Lending pool manager contract.
     * @param systemVariables_ System variables contract.
     */
    constructor(
        address pendingPoolBeacon_,
        address lendingPoolBeacon_,
        address lendingPoolTrancheBeacon_,
        IKasuController kasuController_,
        address lendingPoolManager_,
        ISystemVariables systemVariables_
    ) {
        AddressLib.checkIfZero(pendingPoolBeacon_);
        AddressLib.checkIfZero(lendingPoolBeacon_);
        AddressLib.checkIfZero(lendingPoolTrancheBeacon_);
        AddressLib.checkIfZero(address(kasuController_));
        AddressLib.checkIfZero(lendingPoolManager_);
        AddressLib.checkIfZero(address(systemVariables_));

        _pendingPoolBeacon = pendingPoolBeacon_;
        _lendingPoolBeacon = lendingPoolBeacon_;
        _lendingPoolTrancheBeacon = lendingPoolTrancheBeacon_;
        _kasuController = kasuController_;
        _lendingPoolManager = lendingPoolManager_;
        _systemVariables = systemVariables_;
    }

    /**
     * @notice Creates a lending pool.
     * @param createPoolConfig Configuration for creating a lending pool.
     * @return lendingPoolDeployment Deployment information of the lending pool.
     */
    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        onlyLendingPoolManager
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // verify pool configuration
        AddressLib.checkIfZero(createPoolConfig.poolAdmin);

        if (createPoolConfig.tranches.length < _systemVariables.minTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count less than minimum");
        }

        if (createPoolConfig.tranches.length > _systemVariables.maxTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count more than maximum");
        }

        // deploy lending pool
        BeaconProxy lendingPoolBeaconProxy = new BeaconProxy(_lendingPoolBeacon, "");
        LendingPool lendingPool = LendingPool(address(lendingPoolBeaconProxy));
        lendingPoolDeployment.lendingPool = address(lendingPoolBeaconProxy);

        // deploy tranches
        uint256 trancheCount = createPoolConfig.tranches.length;
        lendingPoolDeployment.tranches = new address[](trancheCount);

        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            lendingPoolDeployment.tranches[i] = _deployLendingPoolTranche(
                createPoolConfig.poolName, createPoolConfig.poolSymbol, i, trancheCount, lendingPool
            );
        }

        // deploy pending pool
        BeaconProxy pendingPoolBeaconProxy = new BeaconProxy(_pendingPoolBeacon, "");
        PendingPool pendingPool = PendingPool(address(pendingPoolBeaconProxy));
        lendingPoolDeployment.pendingPool = address(pendingPool);

        // initialize lending pool
        LendingPoolInfo memory lendingPoolInfo =
            LendingPoolInfo({pendingPool: address(pendingPool), trancheAddresses: lendingPoolDeployment.tranches});

        PoolConfiguration memory poolConfiguration = lendingPool.initialize(createPoolConfig, lendingPoolInfo);

        // initialize pending pool
        (string memory pendingPoolName, string memory pendingPoolSymbol) =
            _pendingPoolName(createPoolConfig.poolName, createPoolConfig.poolSymbol);
        pendingPool.initialize(pendingPoolName, pendingPoolSymbol, lendingPool);

        // set pool admin
        _kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_POOL_ADMIN, createPoolConfig.poolAdmin
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
        BeaconProxy lendingPoolTrancheBeaconProxy = new BeaconProxy(_lendingPoolTrancheBeacon, "");
        LendingPoolTranche lendingPoolTranche = LendingPoolTranche(address(lendingPoolTrancheBeaconProxy));

        (string memory fullTrancheName, string memory fullTrancheSymbol) =
            _trancheName(poolName, poolSymbol, trancheIndex, trancheCount);

        lendingPoolTranche.initialize(fullTrancheName, fullTrancheSymbol, lendingPool);

        return address(lendingPoolTranche);
    }

    function _trancheName(
        string memory lendingPoolName,
        string memory lendingPoolSymbol,
        uint256 trancheIndex,
        uint256 trancheCount
    ) internal view returns (string memory, string memory) {
        TrancheInfo memory trancheNameInfo = _systemVariables.trancheNameInfo(trancheCount, trancheIndex);

        return (
            string.concat(lendingPoolName, " - ", trancheNameInfo.trancheName),
            string.concat(trancheNameInfo.tokenSymbol, "_", lendingPoolSymbol)
        );
    }

    function _pendingPoolName(string memory poolName, string memory lendingPoolSymbol)
        internal
        pure
        returns (string memory, string memory)
    {
        return (string.concat(poolName, " - Request NFT"), string.concat(lendingPoolSymbol, "_RQST"));
    }

    modifier onlyLendingPoolManager() {
        if (msg.sender != _lendingPoolManager) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }
        _;
    }
}
