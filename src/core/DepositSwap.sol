// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISwapper.sol";
import "./interfaces/IWETH9.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";

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

/**
 * @title DepositSwap abstract contract.
 * @notice Helper contract for swapping ERC20 tokens using external exchanges before making a deposit.
 */
abstract contract DepositSwap {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @dev WETH contract.
    IWETH9 private immutable _weth;
    /// @dev Swapper contract.
    ISwapper private immutable _swapper;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param weth_ WETH contract.
     * @param swapper_ Swapper contract.
     */
    constructor(IWETH9 weth_, ISwapper swapper_) {
        AddressLib.checkIfZero(address(weth_));
        AddressLib.checkIfZero(address(swapper_));

        _weth = weth_;
        _swapper = swapper_;
    }

    /* ========== SWAP HELPER FUNCTIONS ========== */

    /**
     * @notice Swaps tokens using the specified swap information.
     * @dev
     * Tokens are transferred from the caller to the swapper.
     * swapper should swap tokens and return the swapped tokens to this contract.
     * @param swapDepositBag Swap and deposit information.
     * @param outToken Expected token to receive.
     * @return tokenAmount Amount of the token received.
     */
    function _transferAndSwap(SwapDepositBag memory swapDepositBag, address outToken) internal returns (uint256) {
        if (swapDepositBag.inTokens.length != swapDepositBag.inAmounts.length) revert InvalidArrayLength();
        uint256 msgValue = msg.value;

        // Wrap ETH if any.
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

    /**
     * @notice Post swap actions.
     * @dev
     * Transfers unswapped tokens back to the caller.
     * Transfers unswapped ETH back to the caller.
     * Transfer unused outToken tokens back to the caller.
     * @param inTokens Swap input tokens array.
     * @param outToken Swap output token.
     */
    function _postSwap(address[] memory inTokens, address outToken) internal {
        // Return in tokens tokens if any left.
        uint256 returnBalance;
        for (uint256 i; i < inTokens.length; ++i) {
            returnBalance = IERC20(inTokens[i]).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(inTokens[i]).safeTransfer(msg.sender, returnBalance);
            }
        }

        // Return outToken if any.
        returnBalance = IERC20(outToken).balanceOf(address(this));
        if (returnBalance > 0) {
            IERC20(outToken).safeTransfer(msg.sender, returnBalance);
        }

        // Return WETH if any.
        if (msg.value > 0) {
            returnBalance = IERC20(address(_weth)).balanceOf(address(this));
            if (returnBalance > 0) {
                IERC20(address(_weth)).safeTransfer(msg.sender, returnBalance);
            }
        }

        // send back ETH if swapper returned eth
        if (address(this).balance > 0) {
            Address.sendValue(payable(msg.sender), address(this).balance);
        }
    }
}
