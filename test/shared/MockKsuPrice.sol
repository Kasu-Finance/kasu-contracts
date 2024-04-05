// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../../src/core/interfaces/IKsuPrice.sol";

contract MockKsuPrice is IKsuPrice {
    uint256 private _ksuTokenPrice;

    function test_mock() external pure {}

    function getKsuTokenPrice() external view returns (uint256) {
        return _ksuTokenPrice;
    }

    function setKsuTokenPrice(uint256 ksuTokenPrice_) external {
        _ksuTokenPrice = ksuTokenPrice_;
    }
}
