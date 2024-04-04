// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

abstract contract rKSU is ERC20Upgradeable {
    error NonTransferrable();

    constructor() {
        _disableInitializers();
    }

    function _initializeRKSU() internal onlyInitializing {
        __ERC20_init("rKasu Token", "rKSU");
    }

    function transfer(address, uint256) public pure override returns (bool) {
        revert NonTransferrable();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NonTransferrable();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert NonTransferrable();
    }
}
