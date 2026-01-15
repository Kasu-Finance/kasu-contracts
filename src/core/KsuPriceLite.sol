// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IKsuPrice.sol";

/**
 * @title KsuPriceLite
 * @notice Lite implementation that returns a zero price.
 */
contract KsuPriceLite is IKsuPrice {
    function ksuTokenPrice() external pure override returns (uint256) {
        return 0;
    }
}
