// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IClearing.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";

abstract contract ClearingCalculations is IClearingCalculations {
    IUserManager private userManager;

    PendingDeposits public pendingDeposits;
    PendingWithdrawals public pendingWithdrawals;

    uint256 private _pendingRequestProcessedIndexCount;

    constructor(IUserManager userManger_) {
        userManager = userManger_;
    }

    function calculatePendingRequestsPriority(uint256 batchSize) external {
        // TODO: check epoch id
        uint256 batchSize_ = getRemainingPendingRequestsPriorityCalculation() >= batchSize
            ? batchSize
            : getRemainingPendingRequestsPriorityCalculation();
        uint256 startingIndexInclusive = _pendingRequestProcessedIndexCount + 1;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;

        for (uint256 i = startingIndexInclusive + 1; i <= endingIndexInclusive; ++i) {
            uint256 userRequestNftId = tokenByIndex(i);
            address pendingRequestOwner = ownerOf(userRequestNftId);
            (, uint256 ownerLoyaltyLevel) = userManager.getUserLoyaltyLevel(pendingRequestOwner);
            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                (address trancheAddress,) = decomposeDepositId(userRequestNftId);
                uint256 trancheIndex = _getTrancheIndex(trancheAddress);

                pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] +=
                    depositNftDetails.assetAmount;
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                (address trancheAddress,) = decomposeWithdrawalId(userRequestNftId);
                uint256 trancheIndex = _getTrancheIndex(trancheAddress);

                ILendingPoolTranche tranche = ILendingPoolTranche(trancheAddress);
                uint256 assetAmount = tranche.convertToAssets(withdrawalNftDetails.sharesAmount);

                pendingWithdrawals.totalWithdrawalsAmount += assetAmount;
                pendingWithdrawals.priorityWithdrawalAmounts[trancheIndex] += assetAmount;
            }
            _pendingRequestProcessedIndexCount = i;
        }
    }

    //*** Helper Methods ***/

    function getRemainingPendingRequestsPriorityCalculation() public view returns (uint256) {
        return totalSupply() - _pendingRequestProcessedIndexCount;
    }

    //*** Virtual Methods ***/

    //getTotalPendingRequests()
    function totalSupply() public view virtual returns (uint256);

    // getPendingRequestIdByIndex
    function tokenByIndex(uint256 index) public view virtual returns (uint256);

    // isPendingRequestDeposit
    function isDepositNft(uint256 nftId) public pure virtual returns (bool);

    // getPendingRequestOwner
    function ownerOf(uint256 tokenId) public view virtual returns (address);

    function decomposeDepositId(uint256 id) public pure virtual returns (address tranche, uint256 depositId);

    function decomposeWithdrawalId(uint256 id) public pure virtual returns (address tranche, uint256 withdrawalId);

    function trancheDepositNftDetails(uint256 dNftId)
        public
        view
        virtual
        returns (DepositNftDetails memory depositNftDetails);

    function trancheWithdrawalNftDetails(uint256 wNftId)
        public
        view
        virtual
        returns (WithdrawalNftDetails memory withdrawalNftDetails);

    function _getTrancheIndex(address tranche) internal virtual returns (uint256);

    //*** Modifiers ***/

    modifier requestsPriorityCalculationShouldNotBePending() {
        if (getRemainingPendingRequestsPriorityCalculation() > 0) {
            revert PendingRequestsPriorityCalculationIsPending();
        }
        _;
    }
}
