// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/lendingPool/ILendingPoolTrancheLoss.sol";
import "../AssetFunctionsBase.sol";

// TODO: add maximum minted total shares

/**
 * @dev
 * - when deposits are cleared, users receive ERC20 receipt tranche tokens
 * - when withdrawals are cleared, assets are sent to the lending pool
 * - when impairment happens, users receive ERC1155 impairment receipt tokens
 */
abstract contract LendingPoolTrancheLoss is ILendingPoolTrancheLoss, ERC1155Upgradeable, AssetFunctionsBase {
    using SafeERC20 for IERC20;

    uint256 public nextLossId;
    bool public isPendingLossMint;

    uint256 public minimumLeftAmountAfterLoss;

    mapping(uint256 lossId => LossDetails lossDetails) private _lossDetails;

    mapping(address user => mapping(uint256 lossId => uint256 claimedAmount)) public userClaimedLosses;

    function __LendingPoolTrancheLoss__init() internal onlyInitializing {
        __ERC1155_init("");
        nextLossId = 1;
    }

    function _getUsers() internal view virtual returns (address[] storage users);

    function _getUserActiveTrancheBalance(address user) internal view virtual returns (uint256);

    function _verifyOnlyOwnLendingPool() internal view virtual;

    function getLossDetails(uint256 lossId) external view override verifyLossId(lossId) returns (LossDetails memory) {
        return _lossDetails[lossId];
    }

    function _registerLoss(uint256 lossAmount, uint256 batchSize)
        internal
        verifyValidLossState
        returns (uint256 lossId)
    {
        address[] storage users = _getUsers();
        uint256 usersCount = users.length;

        lossId = nextLossId;
        _lossDetails[lossId] = LossDetails(lossAmount, usersCount, 0, 0, 0);
        nextLossId++;

        if (usersCount > 0) {
            isPendingLossMint = true;
        }

        emit LossRegistered(lossId, lossAmount, usersCount);

        if (batchSize > 0) {
            _batchMintLossTokens(lossId, batchSize);
        }
    }

    function batchMintLossTokens(uint256 lossId, uint256 batchSize) external verifyLossId(lossId) {
        _batchMintLossTokens(lossId, batchSize);
    }

    function _batchMintLossTokens(uint256 lossId, uint256 batchSize) internal {
        if (_isLossMintingComplete(lossId)) {
            revert LossMintAlreadyComplete(lossId);
        }

        if (batchSize == 0) {
            return;
        }

        uint256 usersCount = _lossDetails[lossId].usersCount;
        uint256 usersMintedCount = _lossDetails[lossId].usersMintedCount;
        uint256 usersLeft = usersCount - usersMintedCount;

        if (batchSize > usersLeft) {
            batchSize = usersLeft;
        }

        address[] storage users = _getUsers();

        uint256 mintToUserIndex = usersMintedCount + batchSize;

        for (uint256 i = usersMintedCount; i < mintToUserIndex; ++i) {
            address user = users[i];
            uint256 userLossShares = _getUserActiveTrancheBalance(user);
            _mintUserLossTokens(user, lossId, userLossShares);
        }

        _lossDetails[lossId].usersMintedCount = mintToUserIndex;

        if (_isLossMintingComplete(lossId)) {
            isPendingLossMint = false;
            emit LossMintingComplete(lossId);
        }
    }

    function _mintUserLossTokens(address to, uint256 lossId, uint256 userLossShares) internal {
        (uint256[] memory ids, uint256[] memory values) = _asSingletonArrays2(lossId, userLossShares);
        _update(address(0), to, ids, values);

        _lossDetails[lossId].totalLossShares += userLossShares;
    }

    function repayLoss(uint256 lossId, uint256 amount) external verifyLossId(lossId) {
        _verifyOnlyOwnLendingPool();
        if (!_isLossMintingComplete(lossId)) {
            revert LossMintingNotYetComplete(lossId);
        }

        _lossDetails[lossId].recoveredAmount += amount;

        _transferAssetsFrom(msg.sender, address(this), amount);
        emit LossReturned(lossId, amount);
    }

    // CLAIM LOSS

    function getUserClaimableLoss(address user, uint256 lossId)
        public
        view
        verifyLossId(lossId)
        returns (uint256 claimableAmount)
    {
        if (!_isLossMintingComplete(lossId)) {
            revert LossMintingNotYetComplete(lossId);
        }

        if (_lossDetails[lossId].totalLossShares > 0) {
            claimableAmount = _lossDetails[lossId].recoveredAmount * balanceOf(user, lossId)
                / _lossDetails[lossId].totalLossShares - userClaimedLosses[user][lossId];
        }
    }

    function claimLoss(address user, uint256 lossId) external returns (uint256 claimedAmount) {
        _verifyOnlyOwnLendingPool();

        claimedAmount = getUserClaimableLoss(user, lossId);
        userClaimedLosses[user][lossId] += claimedAmount;

        _transferAssets(user, claimedAmount);

        emit LossClaimed(user, lossId, claimedAmount);
    }

    // HELPER FUNCTIONS

    function isLossMintingComplete(uint256 lossId) external view verifyLossId(lossId) returns (bool) {
        return _isLossMintingComplete(lossId);
    }

    function _isLossMintingComplete(uint256 lossId) internal view returns (bool) {
        return _lossDetails[lossId].usersCount == _lossDetails[lossId].usersMintedCount;
    }

    function _isLossIdValid(uint256 lossId) internal view {
        if (lossId >= nextLossId || lossId == 0) {
            revert LossIdNotValid(lossId);
        }
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

    modifier verifyLossId(uint256 lossId) {
        _isLossIdValid(lossId);
        _;
    }

    modifier verifyValidLossState() {
        if (isPendingLossMint) {
            revert LossMintingInProgress(nextLossId - 1);
        }
        _;
    }
}
