// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/ISwapper.sol";
import "../shared/CommonErrors.sol";
import "../shared/access/KasuAccessControllable.sol";

contract Swapper is ISwapper, KasuAccessControllable {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ========== STATE VARIABLES ========== */

    /**
     * @dev Exchanges that are allowed to execute a swap.
     */
    mapping(address => bool) private exchangeAllowlist;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param controller_ Access control for Kasu ecosystem.
     */
    constructor(IKasuController controller_) KasuAccessControllable(controller_) {}

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

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
            if (!_isContract(swapInfo[i].swapTarget)) {
                revert AddressNotContract(swapInfo[i].swapTarget);
            }

            if (!exchangeAllowlist[swapInfo[i].swapTarget]) {
                revert ExchangeNotAllowed(swapInfo[i].swapTarget);
            }

            _approveMax(IERC20(swapInfo[i].token), swapInfo[i].swapTarget);

            (bool success, bytes memory data) = swapInfo[i].swapTarget.call(swapInfo[i].swapCallData);
            if (!success) revert(_getRevertMsg(data));
        }

        tokenAmount = IERC20(tokenOut).balanceOf(address(this));
        if (tokenAmount > 0) {
            IERC20(tokenOut).safeTransfer(receiver, tokenAmount);
        }

        // Return unswapped tokens.
        for (uint256 i; i < tokensIn.length; ++i) {
            uint256 tokenInBalance = IERC20(tokensIn[i]).balanceOf(address(this));
            if (tokenInBalance > 0) {
                IERC20(tokensIn[i]).safeTransfer(receiver, tokenInBalance);
            }
        }

        emit Swapped(receiver, tokensIn, tokenOut, amountsIn, tokenAmount);
    }

    function updateExchangeAllowlist(address[] calldata exchanges, bool[] calldata allowed)
        external
        onlyRole(ROLE_KASU_ADMIN, msg.sender)
    {
        if (exchanges.length != allowed.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < exchanges.length; ++i) {
            exchangeAllowlist[exchanges[i]] = allowed[i];

            emit ExchangeAllowlistUpdated(exchanges[i], allowed[i]);
        }
    }

    function _approveMax(IERC20 token, address spender) private {
        token.safeIncreaseAllowance(spender, type(uint256).max);
    }

    /**
     * @dev Gets revert message when a low-level call reverts, so that it can
     * be bubbled-up to caller.
     * @param returnData_ Data returned from reverted low-level call.
     * @return revertMsg Original revert message if available, or default message otherwise.
     */
    function _getRevertMsg(bytes memory returnData_) public pure returns (string memory) {
        // if the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (returnData_.length < 68) {
            return "Swapper::_getRevertMsg: Transaction reverted silently.";
        }

        assembly {
            // slice the sig hash
            returnData_ := add(returnData_, 0x04)
        }

        return abi.decode(returnData_, (string)); // all that remains is the revert string
    }

    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function isExchangeAllowed(address exchange) external view returns (bool) {
        return exchangeAllowlist[exchange];
    }
}
