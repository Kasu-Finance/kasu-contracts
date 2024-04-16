// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/lendingPool/ILendingPoolErrors.sol";

/**
 * @title LendingPoolStoppable abstract contract.
 * @notice Helper contract for stopping the lending pool.
 */
abstract contract LendingPoolStoppable {
    bool public isLendingPoolStopped;

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _isLendingPoolStopped() internal view returns (bool) {
        return isLendingPoolStopped;
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _stopLendingPool() internal {
        isLendingPoolStopped = true;
    }

    /* ========== MODIFIERS ========== */

    modifier lendingPoolShouldNotBeStopped() {
        if (_isLendingPoolStopped()) {
            revert ILendingPoolErrors.LendingPoolIsStopped();
        }
        _;
    }

    modifier lendingPoolShouldBeStopped() {
        if (!_isLendingPoolStopped()) {
            revert ILendingPoolErrors.LendingPoolIsNotStopped();
        }
        _;
    }
}
