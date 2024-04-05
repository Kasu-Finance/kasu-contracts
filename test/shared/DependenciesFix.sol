// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract UpgradeableBeaconFix is UpgradeableBeacon {
    constructor(address implementation_, address initialOwner) UpgradeableBeacon(implementation_, initialOwner) {}
}

contract TransparentUpgradeableProxyFix is TransparentUpgradeableProxy {
    constructor(address _logic, address initialOwner, bytes memory _data)
        TransparentUpgradeableProxy(_logic, initialOwner, _data)
    {}
}

contract ProxyAdminFix is ProxyAdmin {
    constructor(address initialOwner) ProxyAdmin(initialOwner) {}
}
