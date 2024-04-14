// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../shared/AddressLib.sol";

contract KSULockBonus is Initializable {
    using SafeERC20 for IERC20;

    address private _ksuLocking;
    IERC20 private _ksuToken;

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(address ksuLocking_, IERC20 ksuToken_) external initializer {
        AddressLib.checkIfZero(ksuLocking_);
        AddressLib.checkIfZero(address(ksuToken_));

        _ksuLocking = ksuLocking_;
        _ksuToken = ksuToken_;

        _ksuToken.safeIncreaseAllowance(_ksuLocking, type(uint256).max);
    }
}
