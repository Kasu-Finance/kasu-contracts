// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IFeeManager {
    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function emitFees(uint256 amount) external;
    function claimProtocolFees() external;

    /* ========== EVENTS ========== */

    event FeesEmitted(address indexed lendingPoolAddress, uint256 ecosystemFeeAmount, uint256 protocolFeeAmount);
    event ProtocolFeesClaimed(address indexed user, uint256 amount);
}
