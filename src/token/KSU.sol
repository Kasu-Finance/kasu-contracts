// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract KSU is ERC20PermitUpgradeable {
    // TODO: check the exact KSU supply
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;

    function initialize(address recipient) external initializer {
        __ERC20_init("Kasu Token", "KSU");
        __ERC20Permit_init("Kasu Token");

        _mint(recipient, TOTAL_SUPPLY);
    }

    // TODO: add burn function
}
