// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IKasuController.sol";
import "../CommonErrors.sol";
import "./Roles.sol";
import "../AddressLib.sol";

/**
 * @notice Account access role verification middleware.
 */
abstract contract KasuAccessControllable {
    /* ========== CONSTANTS ========== */

    /// @dev Kasu access control manager.
    IKasuController internal immutable _controller;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param controller_ Kasu access control manager.
     */
    constructor(IKasuController controller_) {
        AddressLib.checkIfZero(address(controller_));

        _controller = controller_;
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Reverts if an account is missing a role.
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_controller.hasRole(role, account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, role);
        }
    }

    /**
     * @dev Revert if an account is missing a role for a lending pool.
     * @param lendingPool Address of the lending pool.
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkLendingPoolRole(address lendingPool, bytes32 role, address account) internal view {
        if (!_controller.hasLendingPoolRole(lendingPool, role, account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, role);
        }
    }

    /* ========== MODIFIERS ========== */

    /**
     * @notice Only allows Kasu admin.
     * @dev Reverts when the account fails check.
     */
    modifier onlyAdmin() {
        _checkRole(ROLE_KASU_ADMIN, msg.sender);
        _;
    }

    /**
     * @notice Only allows accounts with granted role.
     * @dev Reverts when the account fails check.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlyRole(bytes32 role, address account) {
        _checkRole(role, account);
        _;
    }

    /**
     * @notice Only allows accounts with granted role for a lending pool.
     * @dev Reverts when the account fails check.
     * @param lendingPool Address of the lending pool.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlyLendingPoolRole(address lendingPool, bytes32 role, address account) {
        _checkLendingPoolRole(lendingPool, role, account);
        _;
    }

    /**
     * @notice Only allows function to be called when system is not paused.
     */
    modifier whenNotPaused() {
        _controller.requireNotPaused();
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
