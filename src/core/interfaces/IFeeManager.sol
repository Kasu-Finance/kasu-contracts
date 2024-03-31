// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IFeeManager {
    /**
     * @notice Splits fees received to ecosystem and protocol based on system configuration. Transfers part the fees
     * received to KSU locking pool. Stores protocol fess until claimed.
     * @dev
     * Must be approved first.
     * @param amount The amount to emit.
     */
    function emitFees(uint256 amount) external;

    /**
     * @notice Transfers protocol fees to receiver.
     */
    function claimProtocolFees() external;

    // EVENTS

    event ProtocolFeesEmitted(address indexed lendingPoolAddress, uint256 amount);

    event ProtocolFeesClaimed(address indexed user, uint256 amount);
}
