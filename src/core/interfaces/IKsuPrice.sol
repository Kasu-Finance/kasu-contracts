// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKsuPrice {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function ksuTokenPrice() external view returns (uint256);
}
