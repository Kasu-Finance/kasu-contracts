// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {NonTransferable} from "../shared/CommonErrors.sol";

/**
 * @title rKSU abstract contract
 * @notice rKSU is an ERC20 token that is non-transferable.
 */
abstract contract rKSU is ERC20Upgradeable {
    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @dev Initializes the rKSU contract.
     */
    function __rKSU__init() internal onlyInitializing {
        __ERC20_init("KSU Rewards Credit", "rKSU");
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /// @notice Token is non-transferable.
    function transfer(address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }

    /// @notice Token is non-transferable.
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }

    /// @notice Token is non-transferable.
    function approve(address, uint256) public pure override returns (bool) {
        revert NonTransferable();
    }
}
