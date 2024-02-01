// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../../src/core/interfaces/IKsuPrice.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

contract MockKsuPrice is IKsuPrice, Initializable {
    uint256 private _ksuTokenPrice;

    function initialize() external initializer {
        _ksuTokenPrice = 2e18;
    }

    function getKsuTokenPrice() external view returns (uint256) {
        return _ksuTokenPrice;
    }

    function setKsuTokenPrice(uint256 ksuTokenPrice_) external {
        _ksuTokenPrice = ksuTokenPrice_;
    }
}
