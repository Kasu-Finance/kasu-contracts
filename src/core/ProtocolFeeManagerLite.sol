// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./FeeManager.sol";

/**
 * @title ProtocolFeeManagerLite
 * @notice Fee manager for Lite deployments where all fees are treated as protocol fees.
 * @dev Ecosystem fees are not distributed in Lite deployments.
 */
contract ProtocolFeeManagerLite is FeeManager {
    constructor(
        address underlyingAsset_,
        ISystemVariables systemVariables_,
        IKasuController controller_,
        IKSULocking ksuLocking_,
        ILendingPoolManager lendingPoolManager_
    ) FeeManager(underlyingAsset_, systemVariables_, controller_, ksuLocking_, lendingPoolManager_) {}

    /**
     * @notice Transfers fee amount from the caller and emits them to the FeeManager contract.
     * @dev Only the valid lending pool can call this function.
     * All fees are treated as protocol fees; no ecosystem fee is distributed.
     * @param amount Amount of fees to emit.
     */
    function emitFees(uint256 amount) external override whenNotPaused {
        if (!_lendingPoolManager.isLendingPool(msg.sender)) {
            revert ILendingPoolErrors.InvalidLendingPool(msg.sender);
        }

        _transferAssetsFrom(msg.sender, address(this), amount);

        totalProtocolFeeAmount += amount;

        emit FeesEmitted(msg.sender, 0, amount);
    }
}
