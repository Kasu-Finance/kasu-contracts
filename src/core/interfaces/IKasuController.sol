// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @notice Used when an account is missing a required role.
 * @param role Required role.
 * @param account Account missing the required role.
 */
error MissingRole(bytes32 role, address account);

/**
 * @notice Used when interacting with Spool when the system is paused.
 */
error SystemPaused();

/**
 * @notice Used when setting lending pool owner
 */
error LendingPoolOwnerAlreadySet(address lendingPool);

/**
 * @notice Used when a contract tries to enter in a non-reentrant state.
 */
error ReentrantCall();

/**
 * @notice Used when a contract tries to call in a non-reentrant function and doesn't have the correct role.
 */
error NoReentrantRole();

interface IKasuController is IAccessControl {
    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Gets owner of a lending pool.
     * @param lendingPool Lending pool.
     * @return owner Owner of the lending pool.
     */
    function lendingPoolOwner(address lendingPool) external view returns (address owner);

    /**
     * @notice Looks if an account has a role for a lending pool.
     * @param lendingPool Address of the lending pool.
     * @param role Role to look for.
     * @param account Account to check.
     * @return hasRole True if account has the role for the lending pool, false otherwise.
     */
    function hasLendingPoolRole(address lendingPool, bytes32 role, address account)
        external
        view
        returns (bool hasRole);

    /**
     * @notice Checks if an account is either Spool admin or admin for a lending pool.
     * @dev The function reverts if account is neither.
     * @param lendingPool Address of the lending pool.
     * @param account to check.
     */
    function checkIsAdminOrVaultAdmin(address lendingPool, address account) external view;

    /**
     * @notice Checks if system is paused or not.
     * @return isPaused True if system is paused, false otherwise.
     */
    function paused() external view returns (bool isPaused);

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Pauses the whole system.
     * @dev Requirements:
     * - caller must have role ROLE_PAUSER
     */
    function pause() external;

    /**
     * @notice Unpauses the whole system.
     * @dev Requirements:
     * - caller must have role ROLE_UNPAUSER
     */
    function unpause() external;

    /**
     * @notice Grants role to an account for a lending pool.
     * @dev Requirements:
     * - caller must have either role ROLE_SPOOL_ADMIN or role ROLE_SMART_VAULT_ADMIN for the lending pool
     * @param lendingPool Address of the lending pool.
     * @param role Role to grant.
     * @param account Account to grant the role to.
     */
    function grantLendingPoolRole(address lendingPool, bytes32 role, address account) external;

    /**
     * @notice Revokes role from an account for a lending pool.
     * @dev Requirements:
     * - caller must have either role ROLE_SPOOL_ADMIN or role ROLE_SMART_VAULT_ADMIN for the lending pool
     * @param lendingPool Address of the lending pool.
     * @param role Role to revoke.
     * @param account Account to revoke the role from.
     */
    function revokeLendingPoolRole(address lendingPool, bytes32 role, address account) external;

    /**
     * @notice Renounce role for a lending pool.
     * @param lendingPool Address of the lending pool.
     * @param role Role to renounce.
     */
    function renounceLendingPoolRole(address lendingPool, bytes32 role) external;

    /**
     * @notice Grant ownership to lending pool and assigns admin role.
     * @dev Ownership can only be granted once and it should be done at vault creation time.
     * @param lendingPool Address of the lending pool.
     * @param owner address to which grant ownership to
     */
    function grantLendingPoolOwnership(address lendingPool, address owner) external;

    /**
     * @notice Checks and reverts if a system has already entered in the non-reentrant state.
     */
    function checkNonReentrant() external view;

    /**
     * @notice Sets the entered flag to true when entering for the first time.
     * @dev Reverts if a system has already entered before.
     */
    function nonReentrantBefore() external;

    /**
     * @notice Resets the entered flag after the call is finished.
     */
    function nonReentrantAfter() external;

    /**
     * @notice Emitted when ownership of a lending pool is granted to an address
     * @param lendingPool Lending pool address
     * @param address_ Address of the new lending pool owner
     */
    event LendingPoolOwnershipGranted(address indexed lendingPool, address indexed address_);

    /**
     * @notice Lending pool specific role was granted
     * @param lendingPool Lending pool address
     * @param role Role ID
     * @param account Account to which the role was granted
     */
    event LendingPoolRoleGranted(address indexed lendingPool, bytes32 indexed role, address indexed account);

    /**
     * @notice Lending pool specific role was revoked
     * @param lendingPool Lending pool address
     * @param role Role ID
     * @param account Account for which the role was revoked
     */
    event LendingPoolRoleRevoked(address indexed lendingPool, bytes32 indexed role, address indexed account);

    /**
     * @notice Lending pool specific role was renounced
     * @param lendingPool Lending pool address
     * @param role Role ID
     * @param account Account that renounced the role
     */
    event LendingPoolRoleRenounced(address indexed lendingPool, bytes32 indexed role, address indexed account);
}
