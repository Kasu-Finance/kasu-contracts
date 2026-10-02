// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./ILendingPoolTrancheLoss.sol";

interface ILendingPoolTranche is ILendingPoolTrancheLoss, IERC4626 {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function userActiveShares(address user) external view returns (uint256);
    function userActiveAssets(address user) external view returns (uint256);
    function isTrancheUser(address user) external view returns (bool);
    function trancheUserCount() external view returns (uint256);
    function calculateMaximumLossAmount() external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function removeUserActiveShares(address user, uint256 shares) external;
    function syncTrancheUser(address user) external;

    /* ========== EVENTS ========== */

    /// @notice A user whose last shares left the tranche was not in the tranche users array (earlier desync).
    /// @dev Raised instead of evicting a different user. Repair: none needed for this user, who has left; run
    /// `syncTrancheUser` for the tranche's other holders if more desync is suspected.
    event TrancheUserNotInArray(address indexed user);
    /// @notice A user holding active shares who was missing from the tranche users array was added back.
    event TrancheUserRestored(address indexed user, uint256 index);
    /// @notice A listed user holding no active shares was removed from the tranche users array.
    event TrancheUserRemoved(address indexed user);
}
