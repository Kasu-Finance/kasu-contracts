// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../../shared/AddressLib.sol";

/**
 * @title LendingPoolHelpers abstract contract.
 * @notice Helper contract for lending pool contracts.
 */
abstract contract LendingPoolHelpers is Initializable, ILendingPoolErrors {
    ILendingPoolManager private immutable __lendingPoolManager;
    ILendingPool private _lendingPool;

    constructor(ILendingPoolManager lendingPoolManager_) {
        AddressLib.checkIfZero(address(lendingPoolManager_));
        __lendingPoolManager = lendingPoolManager_;
        _disableInitializers();
    }

    function __LendingPoolHelpers_init(ILendingPool lendingPool_) internal onlyInitializing {
        AddressLib.checkIfZero(address(lendingPool_));
        _lendingPool = lendingPool_;
    }

    function _ownLendingPool() internal view returns (ILendingPool) {
        return _lendingPool;
    }

    function _lendingPoolManager() internal view returns (address) {
        return address(__lendingPoolManager);
    }

    function _pendingPool() internal view returns (address) {
        return _lendingPool.pendingPool();
    }

    function _onlyOwnLendingPool() internal view {
        if (msg.sender != address(_lendingPool)) {
            revert OnlyOwnLendingPool(msg.sender, address(_lendingPool));
        }
    }

    function _onlyLendingPoolManager() internal view {
        if (msg.sender != _lendingPoolManager()) {
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
