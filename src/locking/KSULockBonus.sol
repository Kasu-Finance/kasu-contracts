// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract KSULockBonus is Initializable {
    address public ksuLocking;
    IERC20 public ksuToken;

    function initialize(address ksuLocking_, IERC20 ksuToken_) external initializer {
        ksuLocking = ksuLocking_;
        ksuToken = ksuToken_;
        ksuToken.approve(ksuLocking, type(uint256).max);
    }
}
