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
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function hasLendingPoolRole(address lendingPool, bytes32 role, address account) external view returns (bool hasRole);

    function requireNotPaused() external view;

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function grantLendingPoolRole(address lendingPool, bytes32 role, address account) external;
    function revokeLendingPoolRole(address lendingPool, bytes32 role, address account) external;
    function renounceLendingPoolRole(address lendingPool, bytes32 role) external;

    function pause() external;
    function unpause() external;

    /* ========== EVENTS ========== */

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
