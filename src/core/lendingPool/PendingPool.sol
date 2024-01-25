// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../AssetFunctionsBase.sol";
import "./LendingPoolHelpers.sol";

/**
 * @dev
 * - when depositing, users receive IERC721 deposit NFTs
 * - when withdrawing, users receive IERC721 withdrawal NFTs
 * - when deposits are accepted, users burn their deposit NFTs
 * - when withdrawals are accepted, users burn their withdrawal NFTs
 */
contract PendingPool is IPendingPool, ERC721Upgradeable, AssetFunctionsBase, LendingPoolHelpers {
    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private _trancheDepositNFTs;
    mapping(address => uint256) private _nextTrancheDepositNFTId;
    /// @notice deposit NFT id => DepositNftDetails
    mapping(uint256 => DepositNftDetails) private _trancheDepositNftDetails;

    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private _trancheWithdrawalNFTs;
    mapping(address => uint256) private _nextTrancheWithdrawalNFTId;
    mapping(uint256 => WithdrawalNftDetails) private _trancheWithdrawalNftDetails;
    mapping(address => uint256) private _userRequestedWithdrawalShares;

    uint256 private constant TRANCHE_START_DEPOSIT_NFT_ID = 0;
    uint256 private constant TRANCHE_START_WITHDRAWAL_NFT_ID = 2 ** 95;

    // id: 256 bits
    // id: tranche address + deposit id
    // id: tranche address + withdrawal id

    // deposit id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 0
    // withdrawal id: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 + 2^95
    // id: tranche address + withdrawal id

    // deposit id: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 + 0
    // withdrawal id: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 + 2^95
    // id: tranche address + withdrawal id

    // deposit id: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC + 0
    // withdrawal id: 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC + 2^95

    // address: 2^160
    // left: 2^96 = 79.228.162.514.264.337.593.543.950.336

    constructor(address underlyingAsset_, ILendingPoolManager lendingPoolManager_)
        AssetFunctionsBase(underlyingAsset_)
        LendingPoolHelpers(lendingPoolManager_)
    {}

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
        }
    }

    // VIEW
    function trancheDepositNftDetails(uint256 dNftId) external view returns (DepositNftDetails memory depositNftDetails) {
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
     * @notice Creates a pending deposit for the user. Transfers asset from user to lending pool
     * @dev Must approve asset token before calling this function
     * @param user The user making the pending deposit
     * @param tranche The user's desired tranche for the pending deposit
     * @param amount The amount that will be transferred to the pending deposit
     * @return dNftID The deposit NFT id that acts as a receipt for the pending deposit
     */
    function requestDeposit(address user, address tranche, uint256 amount)
        external
        onlyLendingPoolManager
        returns (uint256 dNftID)
    {
        // receive the asset from the lending pool manager
        _transferAssetsFrom(msg.sender, address(this), amount);

        dNftID = _nextTrancheDepositNFTId[tranche];
        _nextTrancheDepositNFTId[tranche] = dNftID + 1;

        _trancheDepositNFTs[tranche].push(dNftID);

        _mint(user, dNftID);

        // TODO: get epoch id
        _trancheDepositNftDetails[dNftID] = DepositNftDetails(amount, 0, 0);

        // emit DepositRequested(user, tranche, dNftID, amount);
    }

    function cancelDepositRequest(address user, uint256 dNftID) external canCancel canBurnNft(user, dNftID) {
        DepositNftDetails storage depositNftDetails = _trancheDepositNftDetails[dNftID];

        if (depositNftDetails.assetAmount > 0) {
            revert NoAssetsToCancelDepositRequest(dNftID);
        }

        // Burn the deposit NFT
        _update(address(0), dNftID, address(0));

        delete _trancheDepositNftDetails[dNftID];

        // return funds directly to the user
        _transferAssets(user, depositNftDetails.assetAmount);

        // emit DepositRequestCancelled(user, tranche, dNftID);
    }

    /**
     * @notice Creates a pending withdrawal for the user.
     * @param user The user making the pending withdraw
     * @param tranche The pending withdrawal tranche
     * @param trancheShares tranche shares amount to withdraw
     * @return wNftID the withdrawal NFT id that acts as a receipt for the pending withdrawal
     */
    function requestWithdrawal(address user, address tranche, uint256 trancheShares)
        external
        returns (uint256 wNftID)
    {
        IERC20(tranche).transferFrom(user, address(this), trancheShares);

        wNftID = _nextTrancheWithdrawalNFTId[tranche];
        _nextTrancheWithdrawalNFTId[tranche] = wNftID + 1;

        _trancheWithdrawalNFTs[tranche].push(wNftID);

        _mint(user, wNftID);

        // TODO: get epoch id
        _trancheWithdrawalNftDetails[wNftID] = WithdrawalNftDetails(trancheShares, 0, 0);

        // emit WithdrawalRequested(user, tranche, wNftID, trancheShares);
    }

    function cancelWithdrawalRequest(address user, uint256 wNftID) external canCancel canBurnNft(user, wNftID) {
        WithdrawalNftDetails storage withdrawalNftDetails = _trancheWithdrawalNftDetails[wNftID];

        if (withdrawalNftDetails.sharesAmount > 0) {
            revert NoSharesToCancelWithdrawalRequest(wNftID);
        }

        // Burn the withdrawal NFT
        _update(address(0), wNftID, address(0));

        delete _trancheWithdrawalNftDetails[wNftID];

        // emit WithdrawalRequestCancelled(user, tranche, wNftID);
    }

    // DEPOSIT/WITHDRAWAL ACCEPTANCE

    // probably called by the lending pool
    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external {
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

            delete _trancheDepositNftDetails[dNftID];
        }

        (address tranche,) = decomposeDepositId(dNftID);

        ILendingPool lendingPool = _getOwnLendingPool();

        _approveAsset(address(lendingPool), acceptedAmount);

        lendingPool.acceptDeposit(tranche, user, acceptedAmount);
    }

    function acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) external {
        WithdrawalNftDetails storage withdrawalNftDetails = _trancheWithdrawalNftDetails[wNftID];

        if (withdrawalNftDetails.sharesAmount < acceptedShares) {
            revert TooManySharesRequested(wNftID, withdrawalNftDetails.sharesAmount, acceptedShares);
        }

        unchecked {
            withdrawalNftDetails.sharesAmount -= acceptedShares;
        }

        if (withdrawalNftDetails.sharesAmount == 0) {
            // Burn the deposit NFT
            _update(address(0), wNftID, address(0));

            delete _trancheWithdrawalNftDetails[wNftID];
        }

        (address tranche,) = decomposeWithdrawalId(wNftID);
        address user = ownerOf(wNftID);

        ILendingPool lendingPool = _getOwnLendingPool();
        lendingPool.acceptWithdrawal(tranche, user, acceptedShares);
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

    function _canBurnNft(address user, uint256 nftId) private view {
        if (ownerOf(nftId) != user) {
            revert UserIsNotOwnerOfNFT(user, nftId);
        }
    }

    // MODIFIERS

    modifier canCancel() {
        // TODO: Check if the time is right to cancel deposit request (if it's not clearing period time)
        _;
    }

    modifier canBurnNft(address user, uint256 nftId) {
        _canBurnNft(user, nftId);
        _;
    }
}
