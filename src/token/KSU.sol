// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract KSU is ERC20PermitUpgradeable {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(address recipient) external initializer {
        __ERC20_init("Kasu", "KSU");
        __ERC20Permit_init("Kasu");

        _mint(recipient, TOTAL_SUPPLY);
    }

    /* ========== EXTERNAL MUTATIVE METHODS ========== */

    /**
     * @dev Destroys a `value` amount of tokens from the caller.
     */
    function burn(uint256 value) public {
        _burn(_msgSender(), value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, deducting from
     * the caller's allowance.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `value`.
     */
    function burnFrom(address account, uint256 value) public {
        _spendAllowance(account, _msgSender(), value);
        _burn(account, value);
    }
}
