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
import "../interfaces/IUserManager.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../clearing/PendingRequestsPriorityCalculation.sol";
import "../clearing/ClearingCoordinator.sol";
import "../clearing/AcceptedRequestsExecution.sol";
import "../clearing/ClearingSteps.sol";
import "./UserRequestIds.sol";

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
    LendingPoolStoppable,
    ClearingSteps
{
    ISystemVariables public immutable systemVariables;
    IUserManager public immutable userManager;

    mapping(address => uint256) private _nextTrancheDepositNFTId;

    /// @dev deposit NFT id => DepositNftDetails
    mapping(uint256 => DepositNftDetails) private _trancheDepositNftDetails;

    mapping(address => uint256) private _nextTrancheWithdrawalNFTId;

    /// @dev withdrawal NFT id => WithdrawalNftDetails.
    mapping(uint256 => WithdrawalNftDetails) private _trancheWithdrawalNftDetails;

    // user => epoch => tranche => dNftId
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _dNftIdPerUserPerEpochPerTranche;

    // user => epoch => tranche => priority => wNftId
    mapping(address => mapping(uint256 => mapping(address => mapping(RequestedFrom => uint256)))) private
        _wNftIdPerUserPerEpochPerTranchePerPriority;

    constructor(
        ISystemVariables systemVariables_,
        address underlyingAsset_,
        ILendingPoolManager lendingPoolManager_,
        IUserManager userManger_,
        IAcceptedRequestsCalculation acceptedRequestsCalculation_
    )
        AssetFunctionsBase(underlyingAsset_)
        LendingPoolHelpers(lendingPoolManager_)
        ClearingSteps(acceptedRequestsCalculation_)
    {
        systemVariables = systemVariables_;
        userManager = userManger_;
        _disableInitializers();
    }

    /**
     * @notice Initializes the pending pool.
     * @param name_ The name of the pending NFT.
     * @param symbol_ The symbol of the pending NFT.
     * @param lendingPool_ The address of the lending pool.
     */
    function initialize(string memory name_, string memory symbol_, ILendingPool lendingPool_) public initializer {
        __ERC721_init(name_, symbol_);
        __LendingPoolHelpers_init(lendingPool_);
    }

    function setUpTranches() public {
        address[] memory trancheAddresses = _getOwnLendingPool().lendingPoolInfo().trancheAddresses;
        for (uint256 i; i < trancheAddresses.length; ++i) {
            _nextTrancheDepositNFTId[trancheAddresses[i]] = UserRequestIds.composeDepositId(trancheAddresses[i], 0);
            _nextTrancheWithdrawalNFTId[trancheAddresses[i]] =
                UserRequestIds.composeWithdrawalId(trancheAddresses[i], 0);

            IERC20(trancheAddresses[i]).approve(address(_getOwnLendingPool()), type(uint256).max);
        }
    }

    // VIEW
    function trancheDepositNftDetails(uint256 dNftId)
        public
        view
        override(IPendingPool, ClearingSteps)
        returns (DepositNftDetails memory depositNftDetails)
    {
        return _trancheDepositNftDetails[dNftId];
    }

    function trancheWithdrawalNftDetails(uint256 wNftId)
        public
        view
        override(IPendingPool, ClearingSteps)
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
        verifyTranche(tranche)
        canUserRequestDeposit(user, tranche)
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

            _dNftIdPerUserPerEpochPerTranche[user][requestEpochId][tranche] = dNftID;

            _trancheDepositNftDetails[dNftID] =
                DepositNftDetails(amount, tranche, requestEpochId, 0, RequestedFrom.USER);

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
    function cancelDepositRequest(address user, uint256 dNftID)
        external
        canCancel
        isNftOwner(user, dNftID)
        onlyLendingPoolManager
    {
        _returnDepositRequest(dNftID, user);

        (address tranche,) = UserRequestIds.decomposeDepositId(dNftID);

        emit DepositRequestCancelled(user, tranche, dNftID);
    }

    /**
     * @notice Creates a pending withdrawal for the user.
     * @param user The user making withdrawal request.
     * @param tranche The tranche user is withdrawing from.
     * @param trancheShares amount of tranche shares to withdraw.
     * @return wNftID The withdrawal NFT id that acts as a receipt for the pending withdrawal.
     */
    function requestWithdrawal(address user, address tranche, uint256 trancheShares)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
        returns (uint256 wNftID)
    {
        uint256 requestEpochId = systemVariables.getCurrentRequestEpoch();
        wNftID = _requestWithdrawal(user, tranche, trancheShares, requestEpochId, RequestedFrom.USER);

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

        if (withdrawalNftDetails.requestedFrom == RequestedFrom.SYSTEM) {
            revert WithdrawalRequestIsForced(user, address(_getOwnLendingPool()), wNftID);
        }

        (address tranche,) = UserRequestIds.decomposeWithdrawalId(wNftID);

        // Burn the withdrawal NFT
        _update(address(0), wNftID, address(0));

        IERC20(tranche).transfer(user, withdrawalNftDetails.sharesAmount);

        // delete nft storage
        _deleteWNftDetails(user, wNftID);

        emit WithdrawalRequestCancelled(user, tranche, wNftID);
    }

    function batchForceWithdrawals(ForceWithdrawalInput[] calldata input)
        external
        onlyLendingPoolManager
        returns (uint256[] memory wNftIDs)
    {
        uint256 requestEpochId = systemVariables.getCurrentRequestEpoch();
        wNftIDs = new uint256[](input.length);
        for (uint256 i = 0; i < input.length; ++i) {
            _verifyTranche(input[i].tranche);
            wNftIDs[i] = _requestWithdrawal(
                input[i].user, input[i].tranche, input[i].sharesToWithdraw, requestEpochId, RequestedFrom.SYSTEM
            );
            emit ForceWithdrawalRequested(
                input[i].user, input[i].tranche, wNftIDs[i], requestEpochId, input[i].sharesToWithdraw
            );
        }
    }

    function stop() external onlyOwnLendingPool {
        _stopLendingPool();
    }

    function setApprovalForAll(address, bool) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    function approve(address, uint256) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    function transferFrom(address, address, uint256) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(IERC721, ERC721Upgradeable)
    {
        revert NonTransferable();
    }

    function _requestWithdrawal(
        address user,
        address tranche,
        uint256 sharesToWithdraw,
        uint256 requestEpochId,
        RequestedFrom requestedFrom
    ) internal returns (uint256 wNftID) {
        uint256 remainingUserShares = IERC20(tranche).balanceOf(user);
        if (remainingUserShares < sharesToWithdraw) {
            revert InsufficientSharesBalance(
                user, address(_getOwnLendingPool()), tranche, remainingUserShares, sharesToWithdraw
            );
        }

        IERC20(tranche).transferFrom(user, address(this), sharesToWithdraw);

        // get user's dNftID for current epoch
        wNftID = _wNftIdPerUserPerEpochPerTranchePerPriority[user][requestEpochId][tranche][requestedFrom];

        if (wNftID == 0) {
            // create new wNft
            wNftID = _nextTrancheWithdrawalNFTId[tranche];
            _nextTrancheWithdrawalNFTId[tranche] = _incrementWithdrawalRequestId(wNftID);

            _wNftIdPerUserPerEpochPerTranchePerPriority[user][requestEpochId][tranche][requestedFrom] = wNftID;

            _mint(user, wNftID);

            _trancheWithdrawalNftDetails[wNftID] =
                WithdrawalNftDetails(sharesToWithdraw, tranche, requestEpochId, 0, requestedFrom);
        } else {
            // update existing wNft
            _trancheWithdrawalNftDetails[wNftID].sharesAmount += sharesToWithdraw;
        }
    }

    // DEPOSIT/WITHDRAWAL ACCEPTANCE
    function _acceptDepositRequest(uint256 dNftID, address tranche, uint256 acceptedAmount)
        internal
        override
        nftExists(dNftID)
    {
        DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[dNftID];
        if (depositNftDetails.assetAmount < acceptedAmount) {
            revert TooManyAssetsRequested(dNftID, depositNftDetails.assetAmount, acceptedAmount);
        }

        unchecked {
            depositNftDetails.assetAmount -= acceptedAmount;
        }

        address user = ownerOf(dNftID);

        if (depositNftDetails.assetAmount == 0) {
            _burnDepositNft(dNftID);

            _deleteDNftDetails(user, dNftID);
        }

        ILendingPool lendingPool = _getOwnLendingPool();

        _approveAsset(address(lendingPool), acceptedAmount);

        lendingPool.acceptDeposit(tranche, user, acceptedAmount);
    }

    function _rejectDepositRequest(uint256 dNftID) internal override nftExists(dNftID) {
        address user = ownerOf(dNftID);
        _returnDepositRequest(dNftID, user);
        (address tranche,) = UserRequestIds.decomposeDepositId(dNftID);

        emit DepositRequestRejected(user, tranche, dNftID);
    }

    function _returnDepositRequest(uint256 dNftID, address user) private {
        DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[dNftID];

        _burnDepositNft(dNftID);

        // return funds directly to the user
        // NOTE: Maybe verify if there is any assetAmount left or if the deposit was already accepted
        _transferAssets(user, depositNftDetails.assetAmount);

        _deleteDNftDetails(user, dNftID);
    }

    function _burnDepositNft(uint256 dNftID) internal nftExists(dNftID) {
        _update(address(0), dNftID, address(0));
    }

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal override nftExists(wNftID) {
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

            _deleteWNftDetails(user, wNftID);
        }

        (address tranche,) = UserRequestIds.decomposeWithdrawalId(wNftID);

        ILendingPool lendingPool = _getOwnLendingPool();
        lendingPool.acceptWithdrawal(tranche, user, acceptedShares);
    }

    function _deleteDNftDetails(address user, uint256 dNftID) private {
        DepositNftDetails storage dNftDetails = _trancheDepositNftDetails[dNftID];
        delete _dNftIdPerUserPerEpochPerTranche[user][dNftDetails.epochId][dNftDetails.tranche];
        delete _trancheDepositNftDetails[dNftID];
    }

    function _deleteWNftDetails(address user, uint256 wNftID) private {
        WithdrawalNftDetails storage wNftDetails = _trancheWithdrawalNftDetails[wNftID];
        delete _wNftIdPerUserPerEpochPerTranchePerPriority[user][wNftDetails.epochId][wNftDetails.tranche][wNftDetails.requestedFrom];
        delete _trancheWithdrawalNftDetails[wNftID];
    }

    // ID

    // deposit id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 0
    // withdrawal id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 2^95
    // id: withdrawal id (12 bytes), tranche address (20bytes)
    // 000000000000000000000000 0000000000000000000000000000000000000000

    function getUserPendingDepositAmount(address user, uint256 depositEpochId)
        external
        view
        returns (uint256 pendingDepositAmount)
    {
        uint256 ownerNftCount = balanceOf(user);

        for (uint256 i; i < ownerNftCount; ++i) {
            uint256 nftId = tokenOfOwnerByIndex(user, i);
            if (UserRequestIds.isDepositNft(nftId)) {
                DepositNftDetails memory depositNftDetails = _trancheDepositNftDetails[nftId];
                if (depositNftDetails.epochId <= depositEpochId) {
                    pendingDepositAmount += depositNftDetails.assetAmount;
                }
            }
        }
    }

    function _isNftOwner(address user, uint256 nftId) private view {
        if (ownerOf(nftId) != user) {
            revert UserIsNotOwnerOfNFT(user, nftId);
        }
    }

    function _incrementDepositRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 depositId) = UserRequestIds.decomposeDepositId(id);
        incrementedId = UserRequestIds.composeDepositId(tranche, depositId + 1);
    }

    function _incrementWithdrawalRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 withdrawalId) = UserRequestIds.decomposeWithdrawalId(id);
        incrementedId = UserRequestIds.composeWithdrawalId(tranche, withdrawalId + 1);
    }

    function _verifyTranche(address tranche) private view {
        if (!_getOwnLendingPool().isLendingPoolTranche(tranche)) {
            revert InvalidTranche(address(_getOwnLendingPool()), tranche);
        }
    }

    // OVERRIDES: PendingRequestsPriorityCalculation

    function _getTotalPendingRequests() internal view override returns (uint256) {
        return totalSupply();
    }

    function _getPendingRequestIdByIndex(uint256 index) internal view override returns (uint256) {
        return tokenByIndex(index);
    }

    function _getPendingRequestOwner(uint256 tokenId) internal view override returns (address) {
        return ownerOf(tokenId);
    }

    function _getTrancheIndex(address tranche) internal view override returns (uint256) {
        return _getOwnLendingPool().getTrancheIndex(tranche);
    }

    function _getTrancheCount() internal view override returns (uint256) {
        return _getOwnLendingPool().lendingPoolInfo().trancheAddresses.length;
    }

    function _getTranche(uint256 index) internal view override returns (address) {
        return _getOwnLendingPool().lendingPoolInfo().trancheAddresses[index];
    }

    function _isClearingTime() internal view override returns (bool) {
        return systemVariables.isClearingTime();
    }

    function _getUserLoyaltyLevel(address pendingRequestOwner, uint256 epoch)
        internal
        view
        override
        returns (uint256)
    {
        return userManager.getCalculatedUserEpochLoyaltyLevel(pendingRequestOwner, epoch);
    }

    function _getLoyaltyLevelCount() internal view override returns (uint256) {
        return systemVariables.loyaltyThresholds().length + 1;
    }

    function _setDepositRequestPriority(uint256 dNftId, uint256 priority) internal override {
        _trancheDepositNftDetails[dNftId].priority = priority;
    }

    function _setWithdrawalRequestPriority(uint256 wNftId, uint256 priority) internal override {
        _trancheWithdrawalNftDetails[wNftId].priority = priority;
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

    modifier canUserRequestDeposit(address user, address tranche) {
        address[] memory trancheAddresses = _getOwnLendingPool().lendingPoolInfo().trancheAddresses;
        if (trancheAddresses.length <= 1) return;
        if (trancheAddresses[0] == tranche && !userManager.canUserDepositInJuniorTranche(user)) {
            revert IPendingPool.UserCanOnlyDepositInJuniorTrancheIfHeHasLockedRKsu(user);
        }
        _;
    }

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }
}
