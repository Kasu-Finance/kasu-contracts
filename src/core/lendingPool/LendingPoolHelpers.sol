// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";

abstract contract LendingPoolHelpers is Initializable, ILendingPoolErrors {
    ILendingPoolManager public immutable lendingPoolManager;
    ILendingPool private _lendingPool;

    constructor(ILendingPoolManager lendingPoolManager_) {
        lendingPoolManager = lendingPoolManager_;
    }

    function __LendingPoolHelpers_init(ILendingPool lendingPool_) internal onlyInitializing {
        _lendingPool = lendingPool_;
    }

    function _getOwnLendingPool() internal view returns (ILendingPool) {
        return _lendingPool;
    }

    function _getLendingPoolManager() internal view returns (address) {
        return address(lendingPoolManager);
    }

    function _getPendingPool() internal view returns (address) {
        return _lendingPool.getPendingPool();
    }

    function _onlyOwnLendingPool() internal view {
        if (msg.sender != address(_lendingPool)) {
            revert OnlyOwnLendingPool(msg.sender, address(_lendingPool));
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
