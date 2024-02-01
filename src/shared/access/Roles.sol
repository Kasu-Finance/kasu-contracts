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

bytes32 constant ROLE_LENDING_POOL_ADMIN = keccak256("ROLE_LENDING_POOL_ADMIN");
bytes32 constant ROLE_LENDING_POOL_LOAN_ADMIN = keccak256("ROLE_LENDING_POOL_LOAN_ADMIN");
bytes32 constant ROLE_LENDING_POOL_CREATOR = keccak256("ROLE_LENDING_POOL_CREATOR");
