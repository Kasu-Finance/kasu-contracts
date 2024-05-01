// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/ISystemVariables.sol";
import "../interfaces/IUserManager.sol";
import "../clearing/ClearingSteps.sol";
import "../AssetFunctionsBase.sol";
import "./LendingPoolHelpers.sol";
import "./LendingPoolStoppable.sol";
import "./UserRequestIds.sol";
import "../../shared/CommonErrors.sol";
import "../../shared/AddressLib.sol";

/**
 * @title PendingPool contract.
 * @notice Contract for managing pending deposits and withdrawal requests.
 * @dev When depositing, user receives ERC721 deposit NFT (dNFT) in exchange for the deposited asset.
 * When withdrawing, user receives ERC721 withdrawal NFT (wNFT) in exchange for the tranche shares.
 * Deposit and withdrawal request ids are composed of the tranche address and a unique sequential id.
 * When deposit is fully accepted or rejected, user's NFT is burned and the asset is transferred to the lending pool.
 *   User receives tranche shares in exchange.
 * When withdrawal is fully accepted, user's NFT is burned and the tranche shares are transferred to the lending pool.
 *   User receives the asset in exchange.
 * Clearing logic is also part of the PendingPool contract, it can be found in ClearingSteps contract.
 * Clearing requires looping over user pending requests. ERC721Enumerable is used to loop over the request NFTs.
 */
contract PendingPool is
    IPendingPool,
    ERC721EnumerableUpgradeable,
    AssetFunctionsBase,
    LendingPoolHelpers,
    LendingPoolStoppable,
    ClearingSteps
{
    using SafeERC20 for IERC20;

    /// @notice System variables contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ISystemVariables private immutable _systemVariables;
    /// @notice User manager contract.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IUserManager private immutable _userManager;

    /// @dev tranche address => next deposit NFT id
    mapping(address tranche => uint256 dNftId) private _nextTrancheDepositNFTId;

    /// @dev deposit NFT id => DepositNftDetails
    mapping(uint256 dNftId => DepositNftDetails) private _trancheDepositNftDetails;

    /// @dev user => epoch => tranche => dNftId
    /// Used to track user's deposit NFTs for each epoch and tranche. If user deposits in same epoch and tranche multiple times, the same dNFT is reused.
    mapping(address user => mapping(uint256 epoch => mapping(address tranche => uint256 dNftId))) private
        _dNftIdPerUserPerEpochPerTranche;

    /// @dev tranche address => next deposit NFT id
    mapping(address tranche => uint256 wNFT) private _nextTrancheWithdrawalNFTId;

    /// @dev withdrawal NFT id => WithdrawalNftDetails.
    mapping(uint256 wNFT => WithdrawalNftDetails) private _trancheWithdrawalNftDetails;

    /// @dev user => epoch => tranche => RequestedFrom => wNftId
    /// Used to track user's withdrawal NFTs for each epoch, tranche and the request source (either user or a force withdrawal).
    /// If user withdraws in same epoch, tranche and request source multiple times, the same wNFT is reused.
    mapping(
        address user
            => mapping(
                uint256 epoch => mapping(address tranche => mapping(RequestedFrom requestedFrom => uint256 wNftId))
            )
    ) private _wNftIdPerUserPerEpochPerTranchePerPriority;

    /// @notice Total pending deposit amount.
    uint256 public totalPendingDepositAmount;

    /// @dev epoch => total pending deposit amount for the epoch
    mapping(uint256 epoch => uint256 totalEpochPendingDepositAmount) private _totalEpochPendingDepositAmount;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param systemVariables_ System variables contract.
     * @param underlyingAsset_ Underlying asset address.
     * @param lendingPoolManager_ Lending pool manager address.
     * @param userManger_ User manager address.
     * @param clearingCoordinator_ Clearing coordinator address.
     * @param acceptedRequestsCalculation_ Accepted requests calculation contract.
     */
    constructor(
        ISystemVariables systemVariables_,
        address underlyingAsset_,
        ILendingPoolManager lendingPoolManager_,
        IUserManager userManger_,
        IClearingCoordinator clearingCoordinator_,
        IAcceptedRequestsCalculation acceptedRequestsCalculation_
    )
        AssetFunctionsBase(underlyingAsset_)
        LendingPoolHelpers(lendingPoolManager_)
        ClearingSteps(clearingCoordinator_, acceptedRequestsCalculation_)
    {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(address(userManger_));

        _systemVariables = systemVariables_;
        _userManager = userManger_;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the pending pool.
     * @param name_ The name of the pending NFT.
     * @param symbol_ The symbol of the pending NFT.
     * @param lendingPool_ The address of the lending pool.
     */
    function initialize(string memory name_, string memory symbol_, ILendingPool lendingPool_) external initializer {
        __ERC721_init(name_, symbol_);
        __LendingPoolHelpers_init(lendingPool_);

        _setUpTranches();
    }

    function _setUpTranches() private {
        address[] memory trancheAddresses = _ownLendingPool().lendingPoolTranches();
        for (uint256 i; i < trancheAddresses.length; ++i) {
            _nextTrancheDepositNFTId[trancheAddresses[i]] = UserRequestIds.composeDepositId(trancheAddresses[i], 0);
            _nextTrancheWithdrawalNFTId[trancheAddresses[i]] =
                UserRequestIds.composeWithdrawalId(trancheAddresses[i], 0);
        }
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the deposit NFT details.
     * @param dNftId The deposit NFT id.
     * @return depositNftDetails The deposit NFT details.
     */
    function trancheDepositNftDetails(uint256 dNftId)
        public
        view
        override(IPendingPool, ClearingSteps)
        returns (DepositNftDetails memory depositNftDetails)
    {
        return _trancheDepositNftDetails[dNftId];
    }

    /**
     * @notice Returns the withdrawal NFT details.
     * @param wNftId The withdrawal NFT id.
     * @return withdrawalNftDetails The withdrawal NFT details.
     */
    function trancheWithdrawalNftDetails(uint256 wNftId)
        public
        view
        override(IPendingPool, ClearingSteps)
        returns (WithdrawalNftDetails memory withdrawalNftDetails)
    {
        return _trancheWithdrawalNftDetails[wNftId];
    }

    /**
     * @notice Returns the amount of pending deposit for the user for the given epoch or earlier.
     * @param user The user to check.
     * @param depositEpochId The deposit epoch id.
     * @return pendingDepositAmount The amount of pending deposit for the user for the given epoch or earlier.
     */
    function userPendingDepositAmount(address user, uint256 depositEpochId)
        external
        view
        returns (uint256 pendingDepositAmount)
    {
        uint256 ownerNftCount = balanceOf(user);

        for (uint256 i; i < ownerNftCount; ++i) {
            uint256 nftId = tokenOfOwnerByIndex(user, i);
            if (UserRequestIds.isDepositNft(nftId)) {
                DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[nftId];
                if (depositNftDetails.epochId <= depositEpochId) {
                    pendingDepositAmount += depositNftDetails.assetAmount;
                }
            }
        }
    }

    /**
     * @notice Returns the total pending deposit amount for the current epoch.
     * @dev Exclude the next epoch's pending deposit amount from total pending deposit amount.
     * @return The total pending deposit amount for the current epoch.
     */
    function pendingDepositAmountForCurrentEpoch() external view returns (uint256) {
        uint256 currentEpoch = _systemVariables.currentEpochNumber();
        return totalPendingDepositAmount - _totalEpochPendingDepositAmount[currentEpoch + 1];
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // DEPOSIT/WITHDRAWAL REQUESTS

    /**
     * @notice Creates a pending deposit for the user.
     * @dev Transfers asset from lending pool manager to the pending pool.
     * If the deposit is done during the clearing period the deposit is set for the next epoch.
     * If user already deposited in the current epoch, and tranche the same deposit NFT is reused and requested asset amount increased.
     * @param user The user requesting the deposit.
     * @param tranche The user's desired tranche for the deposit.
     * @param amount The requested deposit amount.
     * @return dNftID The deposit NFT id that acts as a receipt for the requested deposit.
     */
    function requestDeposit(address user, address tranche, uint256 amount)
        external
        lendingPoolShouldNotBeStopped
        onlyLendingPoolManager
        verifyTranche(tranche)
        canUserRequestDeposit(user, tranche)
        returns (uint256 dNftID)
    {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        // receive the asset from the lending pool manager
        _transferAssetsFrom(msg.sender, address(this), amount);

        uint256 requestEpochId = _systemVariables.currentRequestEpoch();

        // get user's dNftID for current epoch
        dNftID = _dNftIdPerUserPerEpochPerTranche[user][requestEpochId][tranche];

        if (dNftID == 0) {
            // create new dNft
            dNftID = _nextTrancheDepositNFTId[tranche];
            _nextTrancheDepositNFTId[tranche] = _incrementDepositRequestId(dNftID);

            _dNftIdPerUserPerEpochPerTranche[user][requestEpochId][tranche] = dNftID;

            _trancheDepositNftDetails[dNftID] = DepositNftDetails(amount, tranche, uint64(requestEpochId), 0);

            _mint(user, dNftID);
        } else {
            // update existing dNft
            _trancheDepositNftDetails[dNftID].assetAmount += amount;
        }

        ILendingPool lendingPool = _ownLendingPool();

        // verify the request is between min and max deposit amount
        (uint256 minDepositAmount, uint256 maxDepositAmount) = lendingPool.trancheConfigurationDepositLimits(tranche);
        uint256 totalDeposited = _trancheDepositNftDetails[dNftID].assetAmount;
        if (totalDeposited < minDepositAmount) {
            revert RequestDepositAmountLessThanMinimumAllowed(
                address(lendingPool), tranche, minDepositAmount, totalDeposited, amount
            );
        }

        if (totalDeposited > maxDepositAmount) {
            revert RequestDepositAmountMoreThanMaximumAllowed(
                address(lendingPool), tranche, maxDepositAmount, totalDeposited, amount
            );
        }

        _increasePendingDepositAmount(requestEpochId, amount);

        emit DepositRequested(user, tranche, dNftID, requestEpochId, amount);
    }

    /**
     * @notice Cancels a pending deposit for the user.
     * @dev Transfers asset from the pending pool back to the user.
     * Burns the deposit NFT.
     * Can only cancel if the lending pool is not pending clearing.
     * @param user The user cancelling the deposit.
     * @param dNftID The deposit id to cancel.
     */
    function cancelDepositRequest(address user, uint256 dNftID)
        external
        onlyLendingPoolManager
        canCancel
        isNftOwner(user, dNftID)
        verifyDepositNft(dNftID)
    {
        _returnDepositRequest(dNftID, user);

        (address tranche,) = UserRequestIds.decomposeDepositId(dNftID);

        emit DepositRequestCancelled(user, tranche, dNftID);
    }

    /**
     * @notice Creates a pending withdrawal for the user.
     * @dev Transfers tranche shares from the user to the pending pool.
     * If the withdrawal is done during the clearing period the deposit is set for the next epoch.
     * If user already withdrew in the current epoch, and tranche the same withdrawal NFT is reused and requested share amount increased.
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
        uint256 requestEpochId = _systemVariables.currentRequestEpoch();
        wNftID = _requestWithdrawal(user, tranche, trancheShares, requestEpochId, RequestedFrom.USER);

        emit WithdrawalRequested(user, tranche, wNftID, requestEpochId, trancheShares);
    }

    /**
     * @notice Cancels a pending withdrawal request for the user.
     * @dev Transfers tranche shares from the pending pool back to the user.
     * @param user The user cancelling the withdrawal request.
     * @param wNftID The withdrawal id to cancel.
     */
    function cancelWithdrawalRequest(address user, uint256 wNftID)
        external
        onlyLendingPoolManager
        canCancel
        isNftOwner(user, wNftID)
        verifyWithdrawalNft(wNftID)
    {
        if (_trancheWithdrawalNftDetails[wNftID].requestedFrom == RequestedFrom.SYSTEM) {
            revert CannotCancelSystemWithdrawalRequest(user, wNftID);
        }

        _cancelWithdrawalRequest(user, wNftID);
    }

    /**
     * @notice Force cancels a pending withdrawal request.
     * @dev Transfers tranche shares from the pending pool back to the user.
     * @param wNftID The withdrawal id to cancel.
     */
    function forceCancelWithdrawalRequest(uint256 wNftID)
        external
        onlyLendingPoolManager
        canCancel
        nftExists(wNftID)
        verifyWithdrawalNft(wNftID)
    {
        address user = ownerOf(wNftID);
        _cancelWithdrawalRequest(user, wNftID);
    }

    /**
     * @notice Request a withdrawal by the system for multiple users.
     * @dev These withdrawal requests are forced and cannot be cancelled.
     * Forced withdrawal has the highest priority (above highest standard priority) when clearing.
     * @param input The input data for the forced withdrawals.
     * @return wNftIDs The withdrawal NFT ids that were created.
     */
    function batchForceWithdrawals(ForceWithdrawalInput[] calldata input)
        external
        onlyLendingPoolManager
        returns (uint256[] memory wNftIDs)
    {
        uint256 requestEpochId = _systemVariables.currentRequestEpoch();
        wNftIDs = new uint256[](input.length);
        for (uint256 i; i < input.length; ++i) {
            _verifyTranche(input[i].tranche);
            wNftIDs[i] = _requestWithdrawal(
                input[i].user, input[i].tranche, input[i].sharesToWithdraw, requestEpochId, RequestedFrom.SYSTEM
            );
            emit ForceWithdrawalRequested(
                input[i].user, input[i].tranche, wNftIDs[i], requestEpochId, input[i].sharesToWithdraw
            );
        }
    }

    /**
     * @notice Called when the lending pool is stopped.
     * @dev After the pool is stopped new deposits should be disabled.
     */
    function stop() external onlyOwnLendingPool {
        _stopLendingPool();
    }

    /**
     * @notice Token is non-transferable.
     */
    function setApprovalForAll(address, bool) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    /**
     * @notice Token is non-transferable.
     */
    function approve(address, uint256) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    /**
     * @notice Token is non-transferable.
     */
    function transferFrom(address, address, uint256) public pure override(IERC721, ERC721Upgradeable) {
        revert NonTransferable();
    }

    /**
     * @notice Token is non-transferable.
     */
    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override(IERC721, ERC721Upgradeable)
    {
        revert NonTransferable();
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _canCancel() private view {
        if (_clearingCoordinator.isLendingPoolClearingPending(address(_ownLendingPool()))) {
            revert CannotCancelRequestIfClearingIsPending();
        }
    }

    function _isNftOwner(address user, uint256 nftId) private view {
        if (ownerOf(nftId) != user) {
            revert UserIsNotOwnerOfNFT(user, nftId);
        }
    }

    function _verifyTranche(address tranche) private view {
        if (!_ownLendingPool().isLendingPoolTranche(tranche)) {
            revert InvalidTranche(address(_ownLendingPool()), tranche);
        }
    }

    function _nftExists(uint256 nftId) private view {
        if (_ownerOf(nftId) == address(0)) {
            revert IERC721Errors.ERC721NonexistentToken(nftId);
        }
    }

    function _verifyDepositNft(uint256 nftId) private pure {
        if (!UserRequestIds.isDepositNft(nftId)) {
            revert NotDepositNFT(nftId);
        }
    }

    function _verifyWithdrawalNft(uint256 nftId) private pure {
        if (UserRequestIds.isDepositNft(nftId)) {
            revert NotWithdrawalNFT(nftId);
        }
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _cancelWithdrawalRequest(address user, uint256 wNftID) private {
        uint256 sharesAmount = _trancheWithdrawalNftDetails[wNftID].sharesAmount;

        // Burn the withdrawal NFT
        _burn(wNftID);

        // delete nft storage
        _deleteWNftDetails(user, wNftID);

        (address tranche,) = UserRequestIds.decomposeWithdrawalId(wNftID);

        IERC20(tranche).safeTransfer(user, sharesAmount);

        emit WithdrawalRequestCancelled(user, tranche, wNftID);
    }

    function _requestWithdrawal(
        address user,
        address tranche,
        uint256 sharesToWithdraw,
        uint256 requestEpochId,
        RequestedFrom requestedFrom
    ) internal returns (uint256 wNftID) {
        if (sharesToWithdraw == 0) revert RequestWithdrawSharesAreZero();

        // verify user has enough tranche shares
        uint256 remainingUserShares = IERC20(tranche).balanceOf(user);
        if (remainingUserShares < sharesToWithdraw) {
            revert InsufficientSharesBalance(
                user, address(_ownLendingPool()), tranche, remainingUserShares, sharesToWithdraw
            );
        }

        // transfer tranche shares from user to pending pool
        IERC20(tranche).safeTransferFrom(user, address(this), sharesToWithdraw);

        // get user's wNFT id for current epoch
        wNftID = _wNftIdPerUserPerEpochPerTranchePerPriority[user][requestEpochId][tranche][requestedFrom];

        // if wNFT is not created yet, create new wNFT
        if (wNftID == 0) {
            // create new wNFT
            wNftID = _nextTrancheWithdrawalNFTId[tranche];
            _nextTrancheWithdrawalNFTId[tranche] = _incrementWithdrawalRequestId(wNftID);

            // mint the wNFT
            _mint(user, wNftID);

            // store the wNFT details
            _trancheWithdrawalNftDetails[wNftID] =
                WithdrawalNftDetails(sharesToWithdraw, tranche, uint64(requestEpochId), 0, requestedFrom);

            _wNftIdPerUserPerEpochPerTranchePerPriority[user][requestEpochId][tranche][requestedFrom] = wNftID;
        } else {
            // update existing wNFT
            _trancheWithdrawalNftDetails[wNftID].sharesAmount += sharesToWithdraw;
        }
    }

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
        uint256 epochId = depositNftDetails.epochId;

        if (depositNftDetails.assetAmount == 0) {
            _burn(dNftID);

            _deleteDNftDetails(user, dNftID);
        }

        ILendingPool lendingPool = _ownLendingPool();

        _approveAsset(address(lendingPool), acceptedAmount);

        uint256 trancheSharesMinted = lendingPool.acceptDeposit(tranche, user, acceptedAmount);

        _decreasePendingDepositAmount(epochId, acceptedAmount);

        emit DepositRequestAccepted(user, tranche, dNftID, acceptedAmount, trancheSharesMinted);
    }

    function _rejectDepositRequest(uint256 dNftID) internal override nftExists(dNftID) {
        address user = ownerOf(dNftID);
        _returnDepositRequest(dNftID, user);
        (address tranche,) = UserRequestIds.decomposeDepositId(dNftID);

        emit DepositRequestRejected(user, tranche, dNftID);
    }

    function _returnDepositRequest(uint256 dNftID, address user) private {
        uint256 assetAmount = _trancheDepositNftDetails[dNftID].assetAmount;
        uint256 epochId = _trancheDepositNftDetails[dNftID].epochId;

        _burn(dNftID);

        _deleteDNftDetails(user, dNftID);

        _decreasePendingDepositAmount(epochId, assetAmount);

        // return funds directly to the user
        _transferAssets(user, assetAmount);
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
            _burn(wNftID);

            _deleteWNftDetails(user, wNftID);
        }

        (address tranche,) = UserRequestIds.decomposeWithdrawalId(wNftID);

        ILendingPool lendingPool = _ownLendingPool();
        uint256 assetsWithdrawn = lendingPool.acceptWithdrawal(tranche, user, acceptedShares);

        emit WithdrawalRequestAccepted(user, tranche, wNftID, acceptedShares, assetsWithdrawn);
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

    function _increasePendingDepositAmount(uint256 epoch, uint256 amount) internal {
        _totalEpochPendingDepositAmount[epoch] += amount;
        totalPendingDepositAmount += amount;
    }

    function _decreasePendingDepositAmount(uint256 epoch, uint256 amount) internal {
        _totalEpochPendingDepositAmount[epoch] -= amount;
        totalPendingDepositAmount -= amount;
    }

    function _incrementDepositRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 depositId) = UserRequestIds.decomposeDepositId(id);
        incrementedId = UserRequestIds.composeDepositId(tranche, depositId + 1);
    }

    function _incrementWithdrawalRequestId(uint256 id) private pure returns (uint256 incrementedId) {
        (address tranche, uint256 withdrawalId) = UserRequestIds.decomposeWithdrawalId(id);
        incrementedId = UserRequestIds.composeWithdrawalId(tranche, withdrawalId + 1);
    }

    /* ========== OVERRIDE METHODS ========== */

    function _totalPendingRequests() internal view override returns (uint256) {
        return totalSupply();
    }

    function _pendingRequestIdByIndex(uint256 index) internal view override returns (uint256) {
        return tokenByIndex(index);
    }

    function _pendingRequestOwner(uint256 tokenId) internal view override returns (address) {
        return ownerOf(tokenId);
    }

    function _lendingPoolTranches() internal view override returns (address[] memory) {
        return _ownLendingPool().lendingPoolTranches();
    }

    function _trancheCount() internal view override returns (uint256) {
        return _ownLendingPool().lendingPoolTrancheCount();
    }

    function _userLoyaltyLevel(address pendingRequestOwner, uint256 epoch) internal view override returns (uint8) {
        return _userManager.calculatedUserEpochLoyaltyLevel(pendingRequestOwner, epoch);
    }

    function _loyaltyLevelCount() internal view override returns (uint8) {
        return _systemVariables.loyaltyLevelsCount();
    }

    function _setDepositRequestPriority(uint256 dNftId, uint8 priority) internal override {
        _trancheDepositNftDetails[dNftId].priority = priority;
    }

    function _setWithdrawalRequestPriority(uint256 wNftId, uint8 priority) internal override {
        _trancheWithdrawalNftDetails[wNftId].priority = priority;
    }

    /* ========== MODIFIERS ========== */

    modifier canCancel() {
        _canCancel();
        _;
    }

    modifier isNftOwner(address user, uint256 nftId) {
        _isNftOwner(user, nftId);
        _;
    }

    modifier nftExists(uint256 nftId) {
        _nftExists(nftId);
        _;
    }

    modifier verifyDepositNft(uint256 nftId) {
        _verifyDepositNft(nftId);
        _;
    }

    modifier verifyWithdrawalNft(uint256 nftId) {
        _verifyWithdrawalNft(nftId);
        _;
    }

    modifier canUserRequestDeposit(address user, address tranche) {
        address[] memory trancheAddresses = _ownLendingPool().lendingPoolTranches();
        if (trancheAddresses.length > 1) {
            if (trancheAddresses[0] == tranche && !_userManager.canUserDepositInJuniorTranche(user)) {
                revert IPendingPool.UserCanOnlyDepositInJuniorTrancheIfHeHasLockedRKsu(user);
            }
        }
        _;
    }

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }
}
