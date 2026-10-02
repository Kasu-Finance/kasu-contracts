// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./ILendingPoolTrancheLoss.sol";

interface ILendingPoolTranche is ILendingPoolTrancheLoss, IERC4626 {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function userActiveShares(address user) external view returns (uint256);
    function userActiveAssets(address user) external view returns (uint256);
    function calculateMaximumLossAmount() external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function removeUserActiveShares(address user, uint256 shares) external;
    function syncTrancheUser(address user) external;

    /* ========== EVENTS ========== */

    /// @notice A user whose last shares left the tranche was not at its recorded index in the tranche users array.
    /// @dev Raised instead of evicting a different user. Signals an earlier desync of the tranche users array.
    event TrancheUserIndexMismatch(address indexed user, uint256 recordedIndex);
    /// @notice A user holding active shares who was missing from the tranche users array was added back.
    event TrancheUserRestored(address indexed user, uint256 index);
}
