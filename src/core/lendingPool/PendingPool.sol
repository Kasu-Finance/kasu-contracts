// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../AssetFunctionsBase.sol";

/**
 * @dev
 * - when depositing, users receive IERC721 deposit NFTs
 * - when withdrawing, users receive IERC721 withdrawal NFTs
 * - when deposits are accepted, users burn their deposit NFTs
 * - when withdrawals are accepted, users burn their withdrawal NFTs
 */
contract PendingPool is IPendingPool, ERC721Upgradeable, AssetFunctionsBase {
    struct DepositNftDetails {
        uint256 assetAmount;
        uint256 priorityLevel;
        uint256 epochId;
    }

    struct WithdrawalNftDetails {
        uint256 sharesAmount;
        uint256 priorityLevel;
        uint256 epochId;
    }

    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private trancheDepositNFTs;
    mapping(address => uint256) private nextTrancheDepositNFTId;
    /// @notice deposit NFT id => DepositNftDetails
    mapping(uint256 => DepositNftDetails) private trancheDepositNftDetails;

    /// @dev tranche => nftIDs[]
    mapping(address => uint256[]) private trancheWithdrawalNFTs;
    mapping(address => uint256) private nextTrancheWithdrawalNFTId;
    mapping(uint256 => WithdrawalNftDetails) private trancheWithdrawalNftDetails;

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

    constructor(address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {}

    function initialize(string memory name_, string memory symbol_, address lendingPool, address[] calldata tranches)
        public
        initializer
    {
        __ERC721_init(name_, symbol_);

        for (uint256 i; i < tranches.length; i++) {
            address tranche = tranches[i];
            nextTrancheDepositNFTId[tranche] = composeDepositId(tranche, 0);
            nextTrancheWithdrawalNFTId[tranche] = composeWithdrawalId(tranche, 0);
        }
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
    function requestDeposit(address user, address tranche, uint256 amount) external returns (uint256 dNftID) {
        // receive the asset from the lending pool manager
        _transferAssetsFrom(msg.sender, address(this), amount);

        dNftID = nextTrancheDepositNFTId[tranche];
        nextTrancheDepositNFTId[tranche] = dNftID + 1;

        trancheDepositNFTs[tranche].push(dNftID);

        _mint(user, dNftID);

        // TODO: get epoch id
        trancheDepositNftDetails[dNftID] = DepositNftDetails(amount, 0, 0);

        // emit DepositRequested(user, tranche, dNftID, amount);
    }

    function cancelDepositRequest(address user, uint256 dNftID) external canCancel canBurnNft(user, dNftID) {
        DepositNftDetails storage depositNftDetails = trancheDepositNftDetails[dNftID];

        if (depositNftDetails.assetAmount > 0) {
            revert NoAssetsToCancelDepositRequest(dNftID);
        }

        // Burn the deposit NFT
        _update(address(0), dNftID, address(0));

        delete trancheDepositNftDetails[dNftID];

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
        // TODO: receive the tranche shares from the user/lending pool manager
        wNftID = nextTrancheWithdrawalNFTId[tranche];
        nextTrancheWithdrawalNFTId[tranche] = wNftID + 1;

        trancheWithdrawalNFTs[tranche].push(wNftID);

        _mint(user, wNftID);

        // TODO: get epoch id
        trancheWithdrawalNftDetails[wNftID] = WithdrawalNftDetails(trancheShares, 0, 0);

        // emit WithdrawalRequested(user, tranche, wNftID, trancheShares);
    }

    function cancelWithdrawalRequest(address user, uint256 wNftID) external canCancel canBurnNft(user, wNftID) {
        WithdrawalNftDetails storage withdrawalNftDetails = trancheWithdrawalNftDetails[wNftID];

        if (withdrawalNftDetails.sharesAmount > 0) {
            revert NoSharesToCancelWithdrawalRequest(wNftID);
        }

        // Burn the withdrawal NFT
        _update(address(0), wNftID, address(0));

        delete trancheWithdrawalNftDetails[wNftID];

        // emit WithdrawalRequestCancelled(user, tranche, wNftID);
    }

    // DEPOSIT/WITHDRAWAL ACCEPTANCE

    // probably called by the lending pool
    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external {
        DepositNftDetails storage depositNftDetails = trancheDepositNftDetails[dNftID];

        if (depositNftDetails.assetAmount < acceptedAmount) {
            revert TooManyAssetsRequested(dNftID, depositNftDetails.assetAmount, acceptedAmount);
        }

        depositNftDetails.assetAmount -= acceptedAmount;

        if (depositNftDetails.assetAmount == 0) {
            // Burn the deposit NFT
            _update(address(0), dNftID, address(0));

            delete trancheDepositNftDetails[dNftID];
        }

        // TODO: update accordingly
        address lendingPool = msg.sender;
        _transferAssets(lendingPool, acceptedAmount);
    }

    function composeDepositId(address tranche, uint256 id) internal pure returns (uint256) {
        return uint256(uint160(tranche)) + (id >> 160);
    }

    function decomposeDepositId(uint256 id) internal pure returns (address tranche, uint256 depositId) {
        tranche = address(uint160(id >> 96 << 96));
        depositId = id << 160;
    }

    function composeWithdrawalId(address tranche, uint256 id) internal pure returns (uint256) {
        return uint256(uint160(tranche)) + (id >> 160 + TRANCHE_START_WITHDRAWAL_NFT_ID);
    }

    function decomposeWithdrawalId(uint256 id) internal pure returns (address tranche, uint256 withdrawalId) {
        tranche = address(uint160(id >> 96 << 96));
        withdrawalId = id << 160 - TRANCHE_START_WITHDRAWAL_NFT_ID;
    }

    function _canBurnNft(address user, uint256 nftId) private view {
        if (ownerOf(nftId) != user) {
            revert UserIsNotOwnerOfNFT(user, nftId);
        }
    }

    modifier canCancel() {
        // TODO: Check if the time is right to cancel deposit request (if it's not clearing period time)
        _;
    }

    modifier canBurnNft(address user, uint256 nftId) {
        _canBurnNft(user, nftId);
        _;
    }
}
