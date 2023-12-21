// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IKasuController.sol";
import "../CommonErrors.sol";
import "./Roles.sol";

/**
 * @notice Account access role verification middleware
 */
abstract contract SpoolAccessControllable {
    /* ========== CONSTANTS ========== */

    /**
     * @dev Spool access control manager.
     */
    IKasuController internal immutable controller;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param controller_ Kasu access control manager.
     */
    constructor(IKasuController controller_) {
        if (address(controller_) == address(0)) revert ConfigurationAddressZero();

        controller = controller_;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Reverts if an account is missing a role.\
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!controller.hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @dev Revert if an account is missing a role for a lendingPool.
     * @param lendingPool Address of the smart vault.
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkLendingPoolRole(address lendingPool, bytes32 role, address account) internal view {
        if (!controller.hasLendingPoolRole(lendingPool, role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (controller.paused()) {
            revert SystemPaused();
        }
    }

    function _checkNonReentrant() internal view {
        controller.checkNonReentrant();
    }

    function _nonReentrantBefore() internal {
        controller.nonReentrantBefore();
    }

    function _nonReentrantAfter() internal {
        controller.nonReentrantAfter();
    }

    /* ========== MODIFIERS ========== */

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
     * @notice Only allows accounts with granted role for a smart vault.
     * @dev Reverts when the account fails check.
     * @param lendingPool Address of the smart vault.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlyLendingPoolRole(address lendingPool, bytes32 role, address account) {
        _checkLendingPoolRole(lendingPool, role, account);
        _;
    }

    /**
     * @notice Only allows accounts that are Spool admins or admins of a smart vault.
     * @dev Reverts when the account fails check.
     * @param lendingPool Address of the smart vault.
     * @param account Account to check.
     */
    modifier onlyAdminOrVaultAdmin(address lendingPool, address account) {
        controller.checkIsAdminOrVaultAdmin(lendingPool, account);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Prevents a contract from calling itself, or other contracts using this modifier.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /**
     * @dev Check if a system has already entered in the non-reentrant state.
     */
    modifier checkNonReentrant() {
        _checkNonReentrant();
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
