// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../shared/AddressLib.sol";

/**
 * @title KSULockBonus contract
 * @notice Contract to distribute KSU lock bonuses.
 * @dev Send KSU bonus tokens to this contract to distribute them to the KSU lockers
 * when requested by the KSU locking contract.
 */
contract KSULockBonus is Initializable {
    using SafeERC20 for IERC20;

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the KSULockBonus contract.
     * @dev Allows KSU locking contract to spend KSU bonus tokens.
     * @param ksuLocking Address of the KSU locking contract.
     * @param ksuToken Address of the KSU token.
     */
    function initialize(address ksuLocking, IERC20 ksuToken) external initializer {
        AddressLib.checkIfZero(ksuLocking);
        AddressLib.checkIfZero(address(ksuToken));

        ksuToken.safeIncreaseAllowance(ksuLocking, type(uint256).max);
    }
}
