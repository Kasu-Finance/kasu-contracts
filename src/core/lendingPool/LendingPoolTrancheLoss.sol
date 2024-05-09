// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTrancheLoss.sol";
import "../AssetFunctionsBase.sol";
import "./LendingPoolHelpers.sol";
import "../../shared/CommonErrors.sol";

/**
 * @title Lending Pool Tranche Loss Contract
 * @notice This contract is used to handle the loss of assets in a tranche.
 * @dev When impairment happens, users receive ERC1155 loss receipt tokens with id of the unrealized loss.
 * If the loss is repaid, users can claim their share of the loss.
 * Considering the amount of users, the loss tokens can minted in multiple batches.
 * Tranche share updates should be blocked during the loss token minting.
 */
abstract contract LendingPoolTrancheLoss is
    ILendingPoolTrancheLoss,
    ERC1155Upgradeable,
    AssetFunctionsBase,
    LendingPoolHelpers
{
    /// @notice Minimum amount of assets left in the tranche after a loss.
    uint256 public constant minimumAssetAmountLeftAfterLoss = 10 * 1e6; // 10 USDC

    /// @notice Loss id that is pending for user tokens to be minted.
    /// @dev If 0 then no loss is pending.
    uint256 private _pendingMintLossId;

    /// @dev Loss details for each loss.
    mapping(uint256 lossId => LossDetails lossDetails) private _lossDetails;

    /// @notice User claimed repaid loss amounts for each loss.
    mapping(address user => mapping(uint256 lossId => uint256 claimedAmount)) public userClaimedLosses;

    /* ========== INITIALIZER ========== */

    function __LendingPoolTrancheLoss__init() internal onlyInitializing {
        __ERC1155_init("");
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Gets the loss details for the id.
     * @param lossId The id of the loss.
     * @return lossDetails The loss details.
     */
    function lossDetails(uint256 lossId) external view override returns (LossDetails memory) {
        return _lossDetails[lossId];
    }

    /**
     * @notice Checks if the minting of loss tokens for the id is complete.
     * @param lossId The id of the loss.
     * @return True if minting of unrealized loss tokens for the loss id is complete.
     */
    function isLossMintingComplete(uint256 lossId) external view returns (bool) {
        return _isLossMintingComplete(lossId);
    }

    /**
     * @notice Checks if there is a pending loss mint.
     * @return True if there is a pending loss mint.
     */
    function isPendingLossMint() public view returns (bool) {
        return _pendingMintLossId > 0;
    }

    /**
     * @notice Gets the claimable loss amount for the user and loss id.
     * @param user The user to get the claimable loss for.
     * @param lossId The id of the loss.
     * @return claimableAmount The claimable loss amount.
     */
    function userClaimableLoss(address user, uint256 lossId) public view returns (uint256 claimableAmount) {
        if (!_isLossMintingComplete(lossId)) {
            revert LossMintingNotYetComplete(lossId);
        }

        if (_lossDetails[lossId].totalLossShares > 0) {
            claimableAmount = _lossDetails[lossId].recoveredAmount * balanceOf(user, lossId)
                / _lossDetails[lossId].totalLossShares - userClaimedLosses[user][lossId];
        }
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Registers a loss in the tranche.
     * @param lossId The id of the loss.
     * @param lossAmount The loss amount.
     * @param doMintLossTokens If true, mint all loss tokens to users. If false, only register the loss and mint has to be called separately.
     * @return lossApplied The amount of the loss applied.
     */
    function registerTrancheLoss(uint256 lossId, uint256 lossAmount, bool doMintLossTokens)
        external
        onlyOwnLendingPool
        notPendingLossMint
        returns (uint256 lossApplied)
    {
        uint256 maxLossAmount = _calculateMaximumLossAmount();

        if (lossAmount > 0 && maxLossAmount > 0) {
            // check if total assets can cover the loss
            lossApplied = maxLossAmount >= lossAmount ? lossAmount : maxLossAmount;
            uint256 batchSize = doMintLossTokens ? type(uint256).max : 0;

            _registerLoss(lossId, lossApplied, batchSize);
        }
    }

    /**
     * @notice Mints loss tokens to users for the id.
     * @dev Anyone can call this function to mint loss tokens to users.
     * Tranche share operations should be blocked when there is a pending loss mint.
     * Can only be called when there is a pending loss mint for the id.
     * @param lossId The id of the loss.
     * @param batchSize The amount of users to mint tokens to. If the value is more than remaining users, mint to all remaining users.
     */
    function batchMintLossTokens(uint256 lossId, uint256 batchSize) external {
        if (_pendingMintLossId != lossId || lossId == 0) {
            revert LossMintingNotYetComplete(_pendingMintLossId);
        }

        _batchMintLossTokens(lossId, batchSize);
    }

    /**
     * @notice Repays a loss for the id.
     * @param lossId The id of the loss.
     * @param amount The amount to repay.
     */
    function repayLoss(uint256 lossId, uint256 amount) external onlyOwnLendingPool {
        if (!_isLossMintingComplete(lossId)) {
            revert LossMintingNotYetComplete(lossId);
        }

        _lossDetails[lossId].recoveredAmount += amount;

        _transferAssetsFrom(msg.sender, address(this), amount);
        emit LossReturned(lossId, amount);
    }

    /**
     * @notice Claims a loss for the loss id.
     * @param user The user to claim the loss for.
     * @param lossId The id of the loss.
     * @return claimedAmount The loss amount claimed.
     */
    function claimRepaidLoss(address user, uint256 lossId)
        external
        onlyOwnLendingPool
        returns (uint256 claimedAmount)
    {
        claimedAmount = userClaimableLoss(user, lossId);
        userClaimedLosses[user][lossId] += claimedAmount;

        _transferAssets(user, claimedAmount);

        emit LossClaimed(user, lossId, claimedAmount);
    }

    /**
     * @notice ERC1155 Unrealized loss token is non-transferable.
     */
    function safeTransferFrom(address, address, uint256, uint256, bytes memory)
        public
        pure
        override(ERC1155Upgradeable, IERC1155)
    {
        revert NonTransferable();
    }

    /**
     * @notice ERC1155 Unrealized loss token is non-transferable.
     */
    function setApprovalForAll(address, bool) public pure override(ERC1155Upgradeable, IERC1155) {
        revert NonTransferable();
    }

    /**
     * @notice ERC1155 Unrealized loss token is non-transferable.
     */
    function safeBatchTransferFrom(address, address, uint256[] memory, uint256[] memory, bytes memory)
        public
        override(ERC1155Upgradeable, IERC1155)
    {
        revert NonTransferable();
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _isLossMintingComplete(uint256 lossId) internal view returns (bool) {
        return _lossDetails[lossId].usersCount == _lossDetails[lossId].usersMintedCount;
    }

    /**
     * @dev Creates an array in memory with only one value for each of the elements provided.
     * Taken from OpenZeppelin's ERC1155.sol
     */
    function _asSingletonArrays2(uint256 element1, uint256 element2)
        private
        pure
        returns (uint256[] memory array1, uint256[] memory array2)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Load the free memory pointer
            array1 := mload(0x40)
            // Set array length to 1
            mstore(array1, 1)
            // Store the single element at the next word after the length (where content starts)
            mstore(add(array1, 0x20), element1)

            // Repeat for next array locating it right after the first array
            array2 := add(array1, 0x40)
            mstore(array2, 1)
            mstore(add(array2, 0x20), element2)

            // Update the free memory pointer by pointing after the second array
            mstore(0x40, add(array2, 0x40))
        }
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _registerLoss(uint256 lossId, uint256 lossAmount, uint256 batchSize) internal {
        address[] storage users = _trancheUsersStorage();
        uint256 usersCount = users.length;

        _lossDetails[lossId] = LossDetails(lossAmount, usersCount, 0, 0, 0);

        emit LossRegistered(lossId, lossAmount, usersCount);

        if (usersCount > 0) {
            _pendingMintLossId = lossId;

            if (batchSize > 0) {
                _batchMintLossTokens(lossId, batchSize);
            }
        }
    }

    function _batchMintLossTokens(uint256 lossId, uint256 batchSize) internal {
        uint256 usersMintedCount = _lossDetails[lossId].usersMintedCount;
        uint256 usersLeft = _lossDetails[lossId].usersCount - usersMintedCount;

        if (batchSize > usersLeft) {
            batchSize = usersLeft;
        }

        if (batchSize == 0) {
            return;
        }

        address[] storage users = _trancheUsersStorage();

        uint256 mintToUserIndex = usersMintedCount + batchSize;

        for (uint256 i = usersMintedCount; i < mintToUserIndex; ++i) {
            address user = users[i];
            uint256 userLossShares = _userActiveTrancheBalance(user);
            _mintUserLossTokens(user, lossId, userLossShares);
        }

        _lossDetails[lossId].usersMintedCount = mintToUserIndex;

        emit MintedLossTokensToUsers(lossId, batchSize);

        if (_isLossMintingComplete(lossId)) {
            _pendingMintLossId = 0;
            emit LossMintingComplete(lossId);
        }
    }

    function _mintUserLossTokens(address to, uint256 lossId, uint256 userLossShares) internal {
        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays2(lossId, userLossShares);
        _update(address(0), to, ids, values);

        _lossDetails[lossId].totalLossShares += userLossShares;
    }

    /* ========== VIRTUAL METHODS ========== */

    function _trancheUsersStorage() internal view virtual returns (address[] storage);

    function _userActiveTrancheBalance(address user) internal view virtual returns (uint256);

    function _calculateMaximumLossAmount() internal view virtual returns (uint256 maxLossAmount);

    /* ========== MODIFIERS ========== */

    modifier notPendingLossMint() {
        if (isPendingLossMint()) {
            revert LossMintingInProgress(_pendingMintLossId);
        }
        _;
    }
}
