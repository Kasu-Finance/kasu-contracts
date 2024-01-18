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
import {PendingPool} from "./PendingPool.sol";
import {LendingPoolTranche} from "./LendingPoolTranche.sol";

contract LendingPoolFactory is ILendingPoolFactory {
    function createPool(PoolConfiguration calldata poolConfiguration)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        address lendingPoolAddress = _deployLendingPool(proxyAdmin);
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
        address pendingPoolAddress = _deployPendingPool(proxyAdmin, lendingPoolAddress, tranches);

        lendingPoolDeployment.lendingPool = lendingPoolAddress;
        lendingPoolDeployment.pendingPool = pendingPoolAddress;
        lendingPoolDeployment.tranches = tranches;
    }

    function _deployLendingPool(ProxyAdmin proxyAdmin) internal returns (address) {
        LendingPool lendingPoolIml = new LendingPool();
        TransparentUpgradeableProxy lendingPoolProxy =
            new TransparentUpgradeableProxy(address(lendingPoolIml), address(proxyAdmin), "");
        LendingPool lendingPool = LendingPool(address(lendingPoolProxy));
        lendingPool.initialize("Lending pool token", "LP");
        return address(lendingPool);
    }

    function _deployLendingPoolTranche(
        ProxyAdmin proxyAdmin,
        string memory name,
        string memory symbol,
        address lendingPoolAddress
    ) internal returns (address) {
        LendingPoolTranche lendingPoolTrancheImpl = new LendingPoolTranche();
        TransparentUpgradeableProxy lendingPoolTrancheProxy =
            new TransparentUpgradeableProxy(address(lendingPoolTrancheImpl), address(proxyAdmin), "");
        LendingPoolTranche lendingPoolTranche = LendingPoolTranche(address(lendingPoolTrancheProxy));
        IERC20 lpToken = IERC20(lendingPoolAddress);
        lendingPoolTranche.initialize(name, symbol, lpToken, lendingPoolAddress);
        return address(lendingPoolTranche);
    }

    function _deployPendingPool(ProxyAdmin proxyAdmin, address lendingPoolAddress, address[] memory tranches)
        internal
        returns (address)
    {
        // TODO: update deployment
        PendingPool pendingPoolIml = new PendingPool(address(0));
        TransparentUpgradeableProxy pendingPoolProxy =
            new TransparentUpgradeableProxy(address(pendingPoolIml), address(proxyAdmin), "");
        PendingPool pendingPool = PendingPool(address(pendingPoolProxy));
        pendingPool.initialize("Pending pool token", "PP", lendingPoolAddress, tranches);
        return address(pendingPool);
    }
}
