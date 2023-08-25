// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract KSU is ERC20PermitUpgradeable {
    initialize() external initializer {
        __ERC20Permit_init("Kasu Token", "KSU");
    }
}