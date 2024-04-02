// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IWETH9.sol";
import "../shared/CommonErrors.sol";

/**
 * @notice Input for swapping and depositing assets.
 * @custom:member inTokens Input tokens to be swapped.
 * @custom:member inAmounts Maximal amount of input tokens to be swapped.
 * @custom:member swapInfo Information needed to perform the swap.
 */
struct SwapDepositBag {
    address[] inTokens;
    uint256[] inAmounts;
    SwapInfo[] swapInfo;
}

abstract contract DepositSwap {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IWETH9 private immutable _weth;
    ISwapper private immutable _swapper;

    /* ========== CONSTRUCTOR ========== */

    constructor(IWETH9 weth_, ISwapper swapper_) {
        if (address(weth_) == address(0)) revert ConfigurationAddressZero();
        if (address(swapper_) == address(0)) revert ConfigurationAddressZero();

        _weth = weth_;
        _swapper = swapper_;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function _transferAndSwap(SwapDepositBag memory swapDepositBag, address outToken) internal returns (uint256) {
        if (swapDepositBag.inTokens.length != swapDepositBag.inAmounts.length) revert InvalidArrayLength();
        uint256 msgValue = msg.value;

        //// Wrap eth if needed.
        if (msg.value > 0) {
            _weth.deposit{value: msgValue}();
        }

        // Transfer the tokens from the caller to the swapper.
        for (uint256 i; i < swapDepositBag.inTokens.length; ++i) {
            IERC20(swapDepositBag.inTokens[i]).safeTransferFrom(
                msg.sender, address(_swapper), swapDepositBag.inAmounts[i]
            );

            if (swapDepositBag.inTokens[i] == address(_weth) && msgValue > 0) {
                IERC20(address(_weth)).safeTransfer(address(_swapper), msgValue);
            }
        }

        _swapper.swap(swapDepositBag.inTokens, swapDepositBag.swapInfo, outToken, address(this));

        return IERC20(outToken).balanceOf(address(this));
    }

    function _postSwap(address[] memory inTokens, address outToken) internal {
        // Return unswapped tokens.
        uint256 returnBalance;
        for (uint256 i; i < inTokens.length; ++i) {
            returnBalance = IERC20(inTokens[i]).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(inTokens[i]).safeTransfer(msg.sender, returnBalance);
            }
        }

        returnBalance = IERC20(outToken).balanceOf(address(this));
        if (returnBalance > 0) {
            IERC20(outToken).safeTransfer(msg.sender, returnBalance);
        }

        if (msg.value > 0) {
            returnBalance = IERC20(address(_weth)).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(address(_weth)).safeTransfer(msg.sender, returnBalance);
            }
        }

        // send back eth if swapper returns eth
        if (address(this).balance > 0) {
            payable(msg.sender).transfer(address(this).balance);
        }
    }
}
