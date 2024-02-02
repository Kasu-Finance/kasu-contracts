// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IKsuPrice.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

contract KsuPrice is IKsuPrice, Initializable {
    function initialize() external initializer {}

    function getKsuTokenPrice() external pure returns (uint256) {
        // TODO: implement
        return 2e18;
    }
}
