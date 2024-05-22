// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISwapper.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";

/**
 * @title Swapper contract.
 * @notice Contract for swapping ERC20 tokens using external exchanges.
 */
contract Swapper is ISwapper, KasuAccessControllable {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    /// @dev Exchanges that are allowed to execute a swap.
    mapping(address => bool) private _exchangeAllowlist;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param controller_ Access control for Kasu protocol.
     */
    constructor(IKasuController controller_) KasuAccessControllable(controller_) {}

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Checks if an exchange is allowed to be used in a swap.
     * @param exchange Exchange to check.
     * @return True if the exchange is allowed to be used in a swap, false otherwise.
     */
    function isExchangeAllowed(address exchange) external view returns (bool) {
        return _exchangeAllowlist[exchange];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Swaps tokens using the specified swap targets.
     * @dev Only the swapper role can call the swap function.
     * The tokens that are not swapped are returned to the receiver.
     * swapTarget contracts must be allowed in the exchange allowlist.
     * Swapper will return remaining tokens to the receiver.
     * @param tokensIn Tokens to swap.
     * @param swapInfo Information needed to perform the swap.
     * @param tokenOut Token to receive.
     * @param receiver Receiver of the swapped and remaining tokens.
     * @return tokenAmount Amount of the token received.
     */
    function swap(address[] calldata tokensIn, SwapInfo[] calldata swapInfo, address tokenOut, address receiver)
        external
        onlyRole(ROLE_SWAPPER, msg.sender)
        returns (uint256 tokenAmount)
    {
        if (swapInfo.length == 0 || tokensIn.length == 0 || tokenOut == address(0) || receiver == address(0)) {
            revert InvalidSwapData();
        }

        uint256[] memory amountsIn = new uint256[](tokensIn.length);

        for (uint256 i; i < tokensIn.length; ++i) {
            amountsIn[i] = IERC20(tokensIn[i]).balanceOf(address(this));
        }

        // Perform the swaps.
        for (uint256 i; i < swapInfo.length; ++i) {
            if (!_exchangeAllowlist[swapInfo[i].swapTarget]) {
                revert ExchangeNotAllowed(swapInfo[i].swapTarget);
            }

            _approveMax(IERC20(swapInfo[i].token), swapInfo[i].swapTarget);

            swapInfo[i].swapTarget.functionCall(swapInfo[i].swapCallData);

            _resetApproval(IERC20(swapInfo[i].token), swapInfo[i].swapTarget);
        }

        tokenAmount = IERC20(tokenOut).balanceOf(address(this));
        if (tokenAmount > 0) {
            IERC20(tokenOut).safeTransfer(receiver, tokenAmount);
        }

        // Return remaining tokens.
        for (uint256 i; i < tokensIn.length; ++i) {
            uint256 tokenInBalance = IERC20(tokensIn[i]).balanceOf(address(this));
            if (tokenInBalance > 0) {
                IERC20(tokensIn[i]).safeTransfer(receiver, tokenInBalance);
            }
        }

        emit Swapped(receiver, tokensIn, tokenOut, amountsIn, tokenAmount);
    }

    /**
     * @notice Updates the exchange allowlist.
     * @dev Only the Kasu admin can call this function.
     * @param exchanges Exchanges to update.
     * @param allowed Whether the exchanges are allowed.
     */
    function updateExchangeAllowlist(address[] calldata exchanges, bool[] calldata allowed) external onlyAdmin {
        if (exchanges.length != allowed.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < exchanges.length; ++i) {
            if (!_isContract(exchanges[i])) {
                revert AddressNotContract(exchanges[i]);
            }

            _exchangeAllowlist[exchanges[i]] = allowed[i];

            emit ExchangeAllowlistUpdated(exchanges[i], allowed[i]);
        }
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _approveMax(IERC20 token, address spender) private {
        token.safeIncreaseAllowance(spender, type(uint256).max);
    }

    function _resetApproval(IERC20 token, address spender) private {
        if (token.allowance(address(this), spender) > 0) {
            token.forceApprove(spender, 0);
        }
    }
}
