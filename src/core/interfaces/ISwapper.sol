// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/* ========== STRUCTS ========== */

/**
 * @notice Information needed to make a swap of assets.
 * @custom:member swapTarget Contract executing the swap.
 * @custom:member token Token to be swapped.
 * @custom:member swapCallData Calldata describing the swap itself.
 */
struct SwapInfo {
    address swapTarget;
    address token;
    bytes swapCallData;
}

/* ========== ERRORS ========== */

/**
 * @notice Used when trying to do a swap via an exchange that is not allowed to execute a swap.
 * @param exchange Exchange used.
 */
error ExchangeNotAllowed(address exchange);

/**
 * @notice Used when trying to execute a swap but swap route was not passed.
 */
error InvalidSwapData();

/* ========== INTERFACES ========== */

interface ISwapper {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isExchangeAllowed(address exchange) external view returns (bool isAllowed);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function swap(address[] calldata tokensIn, SwapInfo[] calldata swapInfo, address tokenOut, address receiver)
        external
        returns (uint256 amountOut);

    function updateExchangeAllowlist(address[] calldata exchanges, bool[] calldata allowed) external;

    /* ========== EVENTS ========== */

    event ExchangeAllowlistUpdated(address indexed exchange, bool isAllowed);

    event Swapped(
        address indexed receiver, address[] tokensIn, address tokenOut, uint256[] amountsIn, uint256 amountOut
    );
}
