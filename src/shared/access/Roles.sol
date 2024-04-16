// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/// @dev Kasu Admin role. Equals to the DEFAULT_ADMIN_ROLE of the OpenZeppelin AccessControl.
/// @dev Strongest role in the system. Can update all roles and can set system-wide settings.
bytes32 constant ROLE_KASU_ADMIN = 0x00;

/// @dev Can claim accrued protocol fees.
bytes32 constant ROLE_PROTOCOL_FEE_CLAIMER = keccak256("ROLE_PROTOCOL_FEE_CLAIMER");

/// @dev Lending pool factory role. Can set Pool Admin when creating a new lending pool.
bytes32 constant ROLE_LENDING_POOL_FACTORY = keccak256("ROLE_LENDING_POOL_FACTORY");
/// @dev Can use the Swapper contract. Should be assigned to the LendingPoolManager contract.
bytes32 constant ROLE_SWAPPER = keccak256("ROLE_SWAPPER");

/// @dev Can create new lending pools.
bytes32 constant ROLE_LENDING_POOL_CREATOR = keccak256("ROLE_LENDING_POOL_CREATOR");
/// @dev Pool Admin manages the lending pool roles.
bytes32 constant ROLE_POOL_ADMIN = keccak256("ROLE_POOL_ADMIN");
/// @dev Pool Manager manages the lending pool.
bytes32 constant ROLE_POOL_MANAGER = keccak256("ROLE_POOL_MANAGER");
/// @dev Pool Funds Manager manages the lending pool funds.
bytes32 constant ROLE_POOL_FUNDS_MANAGER = keccak256("ROLE_POOL_FUNDS_MANAGER");
/// @dev Pool Clearing Manager executes the lending pool clearing.
bytes32 constant ROLE_POOL_CLEARING_MANAGER = keccak256("ROLE_POOL_CLEARING_MANAGER");
