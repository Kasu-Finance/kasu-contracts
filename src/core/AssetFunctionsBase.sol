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
    IERC20 public immutable underlyingAsset;

    /**
     * @notice Constructor.
     * @param underlyingAsset_ Underlying asset address.
     */
    constructor(address underlyingAsset_) {
        AddressLib.checkIfZero(underlyingAsset_);
        underlyingAsset = IERC20(underlyingAsset_);
    }

    function _transferAssets(address recipient, uint256 amount) internal {
        underlyingAsset.safeTransfer(recipient, amount);
    }

    function _transferAssetsFrom(address sender, address recipient, uint256 amount) internal {
        underlyingAsset.safeTransferFrom(sender, recipient, amount);
    }

    function _approveAsset(address recipient, uint256 amount) internal {
        underlyingAsset.safeIncreaseAllowance(recipient, amount);
    }

    function _myAssetBalance() internal view returns (uint256) {
        return underlyingAsset.balanceOf(address(this));
    }
}
