// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "../AssetFunctionsBase.sol";
import "./LendingPoolHelpers.sol";
import "./LendingPoolStoppable.sol";

/**
 * @dev
 * - when depositing, users receive IERC721 deposit NFTs
 * - when withdrawing, users receive IERC721 withdrawal NFTs
 * - when deposits are accepted, users burn their deposit NFTs
 * - when withdrawals are accepted, users burn their withdrawal NFTs
 */
contract PendingPool is
    IPendingPool,
    ERC721EnumerableUpgradeable,
    AssetFunctionsBase,
    LendingPoolHelpers,
    LendingPoolStoppable
{
    ISystemVariables public immutable systemVariables;

    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private _trancheDepositNFTs;
    mapping(address => uint256) private _nextTrancheDepositNFTId;

    /// @dev deposit NFT id => DepositNftDetails
    mapping(uint256 => DepositNftDetails) private _trancheDepositNftDetails;

    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private _trancheWithdrawalNFTs;
    mapping(address => uint256) private _nextTrancheWithdrawalNFTId;

    /// @dev withdrawal NFT id => WithdrawalNftDetails.
    mapping(uint256 => WithdrawalNftDetails) private _trancheWithdrawalNftDetails;
    /// @dev user total requested withdrawal tranche shares.
    mapping(address => uint256) private _userRequestedWithdrawalShares;

    uint256 private constant TRANCHE_START_DEPOSIT_NFT_ID = 0;
    uint256 private constant TRANCHE_START_WITHDRAWAL_NFT_ID = 2 ** 95;

    // user => epoch => tranche => dNftId
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _dNftIdPerUserPerEpochPerTranche;

    // user => epoch => tranche => priority => wNftId
    mapping(address => mapping(uint256 => mapping(address => mapping(Priority => uint256)))) private
        _wNftIdPerUserPerEpochPerTranchePerPriority;

    constructor(ISystemVariables systemVariables_, address underlyingAsset_, ILendingPoolManager lendingPoolManager_)
        AssetFunctionsBase(underlyingAsset_)
        LendingPoolHelpers(lendingPoolManager_)
    {
        systemVariables = systemVariables_;
        _disableInitializers();
    }

    /**
     * @notice Initializes the pending pool.
     * @param name_ The name of the pending NFT.
     * @param symbol_ The symbol of the pending NFT.
     * @param lendingPool_ The address of the lending pool.
     * @param tranches The addresses of the tranches.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        ILendingPool lendingPool_,
        address[] calldata tranches
    ) public initializer {
        __ERC721_init(name_, symbol_);
        __LendingPoolHelpers_init(lendingPool_);

        for (uint256 i; i < tranches.length; i++) {
            address tranche = tranches[i];
            _nextTrancheDepositNFTId[tranche] = composeDepositId(tranche, 0);
            _nextTrancheWithdrawalNFTId[tranche] = composeWithdrawalId(tranche, 0);

            IERC20(tranche).approve(address(lendingPool_), type(uint256).max);
        }
    }

    // VIEW
    function trancheDepositNftDetails(uint256 dNftId)
        external
        view
        returns (DepositNftDetails memory depositNftDetails)
    {
        return _trancheDepositNftDetails[dNftId];
    }

    function trancheWithdrawalNftDetails(uint256 wNftId)
        external
        view
        returns (WithdrawalNftDetails memory withdrawalNftDetails)
    {
        return _trancheWithdrawalNftDetails[wNftId];
    }

    // DEPOSIT/WITHDRAWAL REQUESTS

    /**
     * @notice Creates a pending deposit for the user.
     * @dev Transfers asset from lending pool manager to the pending pool.
     * @param user The user requesting the deposit.
     * @param tranche The user's desired tranche for the pending deposit.
     * @param amount The requested deposit amount.
     * @return dNftID The deposit NFT id that acts as a receipt for the pending deposit.
     */
    function requestDeposit(address user, address tranche, uint256 amount)
        external
        lendingPoolShouldNotBeStopped
        onlyLendingPoolManager
        returns (uint256 dNftID)
    {
        // receive the asset from the lending pool manager
        _transferAssetsFrom(msg.sender, address(this), amount);

        uint256 requestEpochId = systemVariables.getCurrentEpochNumber();

        // get user's dNftID for current epoch
        dNftID = _dNftIdPerUserPerEpochPerTranche[user][requestEpochId][tranche];

        if (dNftID == 0) {
            // create new dNft
            dNftID = _nextTrancheDepositNFTId[tranche];
            _nextTrancheDepositNFTId[tranche] = _incrementDepositRequestId(dNftID);

            _trancheDepositNFTs[tranche].push(dNftID);
            _dNftIdPerUserPerEpochPerTranche[user][requestEpochId][tranche] = dNftID;

            _trancheDepositNftDetails[dNftID] = DepositNftDetails(amount, tranche, requestEpochId, Priority.USER);

            _mint(user, dNftID);
        } else {
            // update existing dNft
            _trancheDepositNftDetails[dNftID].assetAmount += amount;
        }

        emit DepositRequested(user, tranche, dNftID, requestEpochId, amount);
    }

    /**
     * @notice Cancels a pending deposit for the user.
     * @dev Transfers asset from the pending pool to the user.
     * @param user The user cancelling the deposit.
     * @param dNftID The deposit id to cancel.
     */
    function cancelDepositRequest(address user, uint256 dNftID) external canCancel isNftOwner(user, dNftID) {
        DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[dNftID];

        // Burn the deposit NFT
        _update(address(0), dNftID, address(0));

        // return funds directly to the user
        // NOTE: Maybe verify if there is any assetAmount left or if the deposit was already accepted
        _transferAssets(user, depositNftDetails.assetAmount);

        _deleteDNftDetails(user, dNftID);

        (address tranche,) = decomposeDepositId(dNftID);

        emit DepositRequestCancelled(user, tranche, dNftID);
    }

    // TODO: check valid tranche with modifier
    /**
     * @notice Creates a pending withdrawal for the user.
     * @param user The user making withdrawal request.
     * @param tranche The tranche user is withdrawing from.
     * @param trancheShares amount of tranche shares to withdraw.
     * @return wNftID The withdrawal NFT id that acts as a receipt for the pending withdrawal.
     */
    function requestWithdrawal(address user, address tranche, uint256 trancheShares)
        external
        returns (uint256 wNftID)
    {
        uint256 requestEpochId = systemVariables.getCurrentRequestEpoch();
        wNftID = _requestWithdrawal(user, tranche, trancheShares, requestEpochId, Priority.USER);

        emit WithdrawalRequested(user, tranche, wNftID, requestEpochId, trancheShares);
    }

    /**
     * @notice Cancels a pending withdrawal request for the user.
     * @dev Transfers tranche shares from the pending pool back to the user.
     * @param user The user cancelling the withdrawal request.
     * @param wNftID The withdrawal id to cancel.
     */
    function cancelWithdrawalRequest(address user, uint256 wNftID) external canCancel isNftOwner(user, wNftID) {
        WithdrawalNftDetails storage withdrawalNftDetails = _trancheWithdrawalNftDetails[wNftID];

        if (withdrawalNftDetails.priorityLevel == Priority.SYSTEM) {
            revert WithdrawalRequestIsForced(user, address(_getOwnLendingPool()), wNftID);
        }

        (address tranche,) = decomposeWithdrawalId(wNftID);

        // Burn the withdrawal NFT
        _update(address(0), wNftID, address(0));

        IERC20(tranche).transfer(user, withdrawalNftDetails.sharesAmount);

        // delete nft storage
        delete _trancheWithdrawalNftDetails[wNftID];

        emit WithdrawalRequestCancelled(user, tranche, wNftID);
    }

    function batchForceWithdrawals(ForceWithdrawalInput[] calldata input)
        external
        onlyLendingPoolManager
        returns (uint256[] memory wNftIDs)
    {
        uint256 requestEpochId = systemVariables.getCurrentRequestEpoch();
        wNftIDs = new uint256[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            wNftIDs[i] = _requestWithdrawal(
                input[i].user, input[i].tranche, input[i].sharesToWithdraw, requestEpochId, Priority.SYSTEM
            );
            emit ForceWithdrawalRequested(
                input[i].user, input[i].tranche, wNftIDs[i], requestEpochId, input[i].sharesToWithdraw
            );
        }
    }

    function stop() external onlyOwnLendingPool {
        _stopLendingPool();
    }

    function _requestWithdrawal(
        address user,
        address tranche,
        uint256 sharesToWithdraw,
        uint256 requestEpochId,
        Priority priority
    ) internal returns (uint256 wNftID) {
        uint256 remainingUserShares = IERC20(tranche).balanceOf(user);
        if (remainingUserShares < sharesToWithdraw) {
            revert InsufficientSharesBalance(
                user, address(_getOwnLendingPool()), tranche, remainingUserShares, sharesToWithdraw
            );
        }

        IERC20(tranche).transferFrom(user, address(this), sharesToWithdraw);

        wNftID = _nextTrancheWithdrawalNFTId[tranche];
        _nextTrancheWithdrawalNFTId[tranche] = _incrementWithdrawalRequestId(wNftID);

        _trancheWithdrawalNFTs[tranche].push(wNftID);

        _mint(user, wNftID);

        _trancheWithdrawalNftDetails[wNftID] = WithdrawalNftDetails(sharesToWithdraw, requestEpochId, priority);
    }

    // DEPOSIT/WITHDRAWAL ACCEPTANCE
    function _acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) internal nftExists(dNftID) {
        DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[dNftID];
        if (depositNftDetails.assetAmount < acceptedAmount) {
            revert TooManyAssetsRequested(dNftID, depositNftDetails.assetAmount, acceptedAmount);
        }

        unchecked {
            depositNftDetails.assetAmount -= acceptedAmount;
        }

        address user = ownerOf(dNftID);

        if (depositNftDetails.assetAmount == 0) {
            // Burn the deposit NFT
            _update(address(0), dNftID, address(0));

            _deleteDNftDetails(user, dNftID);
        }

        (address tranche,) = decomposeDepositId(dNftID);

        ILendingPool lendingPool = _getOwnLendingPool();

        _approveAsset(address(lendingPool), acceptedAmount);

        lendingPool.acceptDeposit(tranche, user, acceptedAmount);
    }

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal nftExists(wNftID) {
        WithdrawalNftDetails storage withdrawalNftDetails = _trancheWithdrawalNftDetails[wNftID];

        if (withdrawalNftDetails.sharesAmount < acceptedShares) {
            revert TooManySharesRequested(wNftID, withdrawalNftDetails.sharesAmount, acceptedShares);
        }

        unchecked {
            withdrawalNftDetails.sharesAmount -= acceptedShares;
        }

        address user = ownerOf(wNftID);

        if (withdrawalNftDetails.sharesAmount == 0) {
            // Burn the deposit NFT
            _update(address(0), wNftID, address(0));

            delete _trancheWithdrawalNftDetails[wNftID];
        }

        (address tranche,) = decomposeWithdrawalId(wNftID);

        ILendingPool lendingPool = _getOwnLendingPool();
        lendingPool.acceptWithdrawal(tranche, user, acceptedShares);
    }

    function _deleteDNftDetails(address user, uint256 dNftID) private {
        DepositNftDetails storage dNftDetails = _trancheDepositNftDetails[dNftID];
        delete _dNftIdPerUserPerEpochPerTranche[user][dNftDetails.epochId][dNftDetails.tranche];
        delete _trancheDepositNftDetails[dNftID];
    }

    // ID

    // id: 256 bits
    // id: tranche address + deposit id
    // id: tranche address + withdrawal id

    // deposit id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 0
    // withdrawal id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 2^95
    // id: withdrawal id (12 bytes), tranche address (20bytes)
    // 000000000000000000000000 0000000000000000000000000000000000000000

    // deposit id: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 + 0
    // withdrawal id: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 + 2^95

    // deposit id: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC + 0
    // withdrawal id: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC + 2^95

    // address: 2^160
    // left: 2^96 = 79.228.162.514.264.337.593.543.950.336

    function getUserPendingAmounts(address user, uint256 depositEpochId)
        external
        view
        returns (uint256 pendingDepositAmount, uint256 pendingWithdrawalAmount)
    {
        uint256 ownerNftCount = balanceOf(user);

        for (uint256 i; i < ownerNftCount; ++i) {
            uint256 nftId = tokenOfOwnerByIndex(user, i);
            if (isDepositNft(nftId)) {
                DepositNftDetails memory depositNftDetails = _trancheDepositNftDetails[nftId];
                if (depositNftDetails.epochId <= depositEpochId) {
                    pendingDepositAmount += depositNftDetails.assetAmount;
                }
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = _trancheWithdrawalNftDetails[nftId];
                (address tranche,) = decomposeWithdrawalId(nftId);
                ILendingPoolTranche lendingPoolTranche = ILendingPoolTranche(tranche);

                pendingWithdrawalAmount += lendingPoolTranche.convertToAssets(withdrawalNftDetails.sharesAmount);
            }
        }
    }

    function composeDepositId(address tranche, uint256 id) public pure returns (uint256) {
        return uint256(uint160(tranche)) | (id << 160);
    }

    function decomposeDepositId(uint256 id) public pure returns (address tranche, uint256 depositId) {
        tranche = address(uint160(id << 96 >> 96));
        depositId = id >> 160;
    }

    function composeWithdrawalId(address tranche, uint256 id) public pure returns (uint256) {
        return uint256(uint160(tranche)) | ((id + TRANCHE_START_WITHDRAWAL_NFT_ID) << 160);
    }

    function decomposeWithdrawalId(uint256 id) public pure returns (address tranche, uint256 withdrawalId) {
        tranche = address(uint160(id << 96 >> 96));
        withdrawalId = (id >> 160) - TRANCHE_START_WITHDRAWAL_NFT_ID;
    }

    function isDepositNft(uint256 nftId) public pure returns (bool) {
        return (nftId >> 160) < TRANCHE_START_WITHDRAWAL_NFT_ID;
    }

    function _isNftOwner(address user, uint256 nftId) private view {
        if (ownerOf(nftId) != user) {
            revert UserIsNotOwnerOfNFT(user, nftId);
        }
    }

    function _incrementDepositRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 depositId) = decomposeDepositId(id);
        incrementedId = composeDepositId(tranche, depositId + 1);
    }

    function _incrementWithdrawalRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 withdrawalId) = decomposeWithdrawalId(id);
        incrementedId = composeWithdrawalId(tranche, withdrawalId + 1);
    }

    // MODIFIERS

    modifier canCancel() {
        if (systemVariables.isClearingTime()) {
            revert CannotCancelDepositDuringClearingPeriod();
        }
        _;
    }

    modifier isNftOwner(address user, uint256 nftId) {
        _isNftOwner(user, nftId);
        _;
    }

    modifier nftExists(uint256 nftId) {
        if (ownerOf(nftId) == address(0)) {
            revert IERC721Errors.ERC721NonexistentToken(nftId);
        }
        _;
    }
}
