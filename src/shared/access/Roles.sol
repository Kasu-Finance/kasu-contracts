// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @dev Grants permission to:
 * - acts as a default admin for other roles,
 *
 * Equals to the DEFAULT_ADMIN_ROLE of the OpenZeppelin AccessControl.
 */
bytes32 constant ROLE_KASU_ADMIN = 0x00;

bytes32 constant ROLE_LENDING_POOL_FACTORY = keccak256("ROLE_LENDING_POOL_FACTORY");

bytes32 constant ROLE_LENDING_POOL_CREATOR = keccak256("ROLE_LENDING_POOL_CREATOR");
bytes32 constant ROLE_POOL_ADMIN = keccak256("ROLE_POOL_ADMIN");
bytes32 constant ROLE_POOL_MANAGER = keccak256("ROLE_POOL_MANAGER");
bytes32 constant ROLE_POOL_FUNDS_MANAGER = keccak256("ROLE_POOL_FUNDS_MANAGER");

bytes32 constant ROLE_PROTOCOL_FEE_CLAIMER = keccak256("ROLE_PROTOCOL_FEE_CLAIMER");
