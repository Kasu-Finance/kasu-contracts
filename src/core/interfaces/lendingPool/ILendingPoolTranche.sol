// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./ILendingPoolTrancheLoss.sol";

interface ILendingPoolTranche is ILendingPoolTrancheLoss, IERC4626, IERC1155 {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function userActiveShares(address user) external view returns (uint256);
    function userActiveAssets(address user) external view returns (uint256);
    function calculateMaximumLossAmount() external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function removeUserActiveShares(address user, uint256 shares) external;
}
