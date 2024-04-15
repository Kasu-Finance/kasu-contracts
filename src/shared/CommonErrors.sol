// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Used when an array has invalid length.
 */
error InvalidArrayLength();

/**
 * @notice Used when configuring an address with a zero address.
 */
error ConfigurationAddressZero();

/**
 * @notice Used when configuration parameters are invalid.
 */
error InvalidConfiguration();

/**
 * @notice Used when doing low-level call on an address that is not a contract.
 * @param address_ Address of the contract
 */
error AddressNotContract(address address_);

/**
 * @notice Used when the external call is not supported.
 */
error NotSupported();

/**
 * @notice Used when the amount should be greater than zero.
 */
error AmountShouldBeGreaterThanZero();

/**
 * @notice Used when the token is non-transferable.
 */
error NonTransferable();

/**
 * @notice Used when an action cannot be executed during clearing time.
 */
error CannotExecuteDuringClearingTime();

/**
 * @notice Used when an action can only be executed during clearing time.
 */
error CanOnlyExecuteDuringClearingTime();
