// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/lendingPool/ILendingPool.sol";

abstract contract LendingPoolStoppable {
    bool public isLendingPoolStopped;

    function _stopLendingPool() internal {
        isLendingPoolStopped = true;
    }

    function _isLendingPoolStopped() internal view returns (bool) {
        return isLendingPoolStopped;
    }

    modifier lendingPoolShouldNotBeStopped() {
        if (_isLendingPoolStopped()) {
            revert ILendingPool.LendingPoolIsStopped();
        }
        _;
    }
}
