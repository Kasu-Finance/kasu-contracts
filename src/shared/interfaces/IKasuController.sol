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
 * @notice Used when interacting with Kasu when the system is paused.
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
    /* ========== EXTERNAL VIEW METHODS ========== */

    /**
     * @notice Gets owner of a lending pool.
     * @param lendingPool Lending pool.
     * @return owner Owner of the lending pool.
     */
    // function lendingPoolOwner(address lendingPool) external view returns (address owner);

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

    function requireNotPaused() external view;

    /* ========== EXTERNAL MUTATIVE METHODS ========== */

    /**
     * @notice Grants role to an account for a lending pool.
     * @dev Requirements:
     * - caller must have either role ROLE_LENDING_POOL_FACTORY or role ROLE_POOL_ADMIN for the lending pool
     * @param lendingPool Address of the lending pool.
     * @param role Role to grant.
     * @param account Account to grant the role to.
     */
    function grantLendingPoolRole(address lendingPool, bytes32 role, address account) external;

    /**
     * @notice Revokes role from an account for a lending pool.
     * @dev Requirements:
     * - caller must have either role ROLE_KASU_ADMIN or role ROLE_POOL_ADMIN for the lending pool
     * @param lendingPool Address of the lending pool.
     * @param role Role to revoke.
     * @param account Account to revoke the role from.
     */
    function revokeLendingPoolRole(address lendingPool, bytes32 role, address account) external;

    function renounceLendingPoolRole(address lendingPool, bytes32 role) external;

    function pause() external;

    function unpause() external;

    /**
     * @notice Renounce role for a lending pool.
     * @param lendingPool Address of the lending pool.
     * @param role Role to renounce.
     */
    // function renounceLendingPoolRole(address lendingPool, bytes32 role) external;

    /**
     * @notice Grant ownership to lending pool and assigns admin role.
     * @dev Ownership can only be granted once and it should be done at vault creation time.
     * @param lendingPool Address of the lending pool.
     * @param owner address to which grant ownership to
     */
    // function grantLendingPoolOwnership(address lendingPool, address owner) external;

    /* ========== EVENTS ========== */

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
