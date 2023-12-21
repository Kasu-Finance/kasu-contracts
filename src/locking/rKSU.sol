// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

abstract contract rKSU is ERC20PermitUpgradeable {
    error NonTransferrable();

    function _initializeRKSU() internal onlyInitializing {
        __ERC20_init("rKasu Token", "rKSU");
    }

    function transfer(address, uint256) public virtual override returns (bool) {
        revert NonTransferrable();
    }

    function transferFrom(address, address, uint256) public virtual override returns (bool) {
        revert NonTransferrable();
    }

    function approve(address, uint256) public virtual override returns (bool) {
        revert NonTransferrable();
    }
}
