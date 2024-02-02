// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKsuPrice {
    function getKsuTokenPrice() external view returns (uint256);
}
