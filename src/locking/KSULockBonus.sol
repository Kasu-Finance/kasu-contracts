// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../shared/AddressLib.sol";

contract KSULockBonus is Initializable {
    using SafeERC20 for IERC20;

    address public ksuLocking;
    IERC20 public ksuToken;

    constructor() {
        _disableInitializers();
    }

    function initialize(address ksuLocking_, IERC20 ksuToken_) external initializer {
        AddressLib.checkIfZero(ksuLocking_);
        AddressLib.checkIfZero(address(ksuToken_));

        ksuLocking = ksuLocking_;
        ksuToken = ksuToken_;

        ksuToken.safeIncreaseAllowance(ksuLocking, type(uint256).max);
    }
}
