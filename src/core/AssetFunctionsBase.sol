// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../shared/AddressLib.sol";

/**
 * @notice Helper abstract contract for interacting with the underlying asset.
 * @dev Asset used in Kasu protocol is USDC and all contracts in the Kasu protocol should have the same asset.
 */
abstract contract AssetFunctionsBase {
    using SafeERC20 for IERC20;

    /// @notice Underlying asset of the contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 internal immutable _underlyingAsset;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param underlyingAsset_ Underlying asset address.
     */
    constructor(address underlyingAsset_) {
        AddressLib.checkIfZero(underlyingAsset_);
        _underlyingAsset = IERC20(underlyingAsset_);
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _transferAssets(address recipient, uint256 amount) internal {
        _underlyingAsset.safeTransfer(recipient, amount);
    }

    function _transferAssetsFrom(address sender, address recipient, uint256 amount) internal {
        _underlyingAsset.safeTransferFrom(sender, recipient, amount);
    }

    function _approveAsset(address recipient, uint256 amount) internal {
        _underlyingAsset.safeIncreaseAllowance(recipient, amount);
    }
}
