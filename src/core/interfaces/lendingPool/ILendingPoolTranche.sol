// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./ILendingPoolTrancheLoss.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
interface ILendingPoolTranche is ILendingPoolTrancheLoss, IERC4626, IERC1155 {
    function removeUserActiveShares(address user, uint256 shares) external;
    function getUserActiveAssets(address user) external view returns (uint256 activeAssets);
    function maximumLossAmount() external view returns (uint256 maxLossAmount);
}
