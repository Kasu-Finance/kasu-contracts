// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/lendingPool/ILendingPoolManager.sol";

abstract contract LendingPoolHelpers {
    error OnlyOwnLendingPool(address sender, address ownLendingPool);
    error OnlyLendingPoolManager();

    ILendingPoolManager public immutable lendingPoolManager;

    constructor(ILendingPoolManager lendingPoolManager_) {
        lendingPoolManager = lendingPoolManager_;
    }

    function _getOwnLendingPool() internal view returns (address) {
        return lendingPoolManager.ownLendingPool(address(this));
    }

    function _getLendingPoolManager() internal view returns (address) {
        return address(lendingPoolManager);
    }

    function _onlyOwnLendingPool() internal view {
        if (msg.sender != _getOwnLendingPool()) {
            revert OnlyOwnLendingPool(msg.sender, _getOwnLendingPool());
        }
    }

    function _onlyLendingPoolManager() internal view {
        if (msg.sender != _getLendingPoolManager()) {
            revert OnlyLendingPoolManager();
        }
    }

    modifier onlyOwnLendingPool() {
        _onlyOwnLendingPool();
        _;
    }

    modifier onlyLendingPoolManager() {
        _onlyLendingPoolManager();
        _;
    }
}
