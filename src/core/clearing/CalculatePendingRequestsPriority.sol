// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/ICalculatePendingRequestsPriority.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import {ISystemVariables} from "../interfaces/ISystemVariables.sol";

abstract contract CalculatePendingRequestsPriority is ICalculatePendingRequestsPriority {
    IUserManager private userManager;
    ISystemVariables private systemVariables;

    PendingDeposits public pendingDeposits;
    PendingWithdrawals public pendingWithdrawals;

    uint256 private _pendingRequestProcessedIndexCount;

    constructor(IUserManager userManger_, ISystemVariables systemVariables_) {
        userManager = userManger_;
        systemVariables = systemVariables_;
    }

    function calculatePendingRequestsPriority(uint256 batchSize) external {
        uint256 batchSize_ = getRemainingPendingRequestsPriorityCalculation() >= batchSize
            ? batchSize
            : getRemainingPendingRequestsPriorityCalculation();
        uint256 startingIndexInclusive = _pendingRequestProcessedIndexCount + 1;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;
        uint256 epochId = systemVariables.getCurrentEpochNumber();

        for (uint256 i = startingIndexInclusive; i <= endingIndexInclusive; ++i) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);
            address pendingRequestOwner = _getPendingRequestOwner(userRequestNftId);
            (, uint256 ownerLoyaltyLevel) = userManager.getUserLoyaltyLevel(pendingRequestOwner);
            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                if (depositNftDetails.epochId != epochId) break;
                (address trancheAddress,) = decomposeDepositId(userRequestNftId);
                uint256 trancheIndex = _getTrancheIndex(trancheAddress);

                pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] +=
                    depositNftDetails.assetAmount;
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                if (withdrawalNftDetails.epochId != epochId) break;
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
        return _getTotalPendingRequests() - _pendingRequestProcessedIndexCount;
    }

    //*** Virtual Methods ***/

    // ERC721
    function _getTotalPendingRequests() internal view virtual returns (uint256);

    function _getPendingRequestIdByIndex(uint256 index) internal view virtual returns (uint256);

    function _getPendingRequestOwner(uint256 tokenId) internal view virtual returns (address);

    // Pending Pool
    function isDepositNft(uint256 nftId) public pure virtual returns (bool);

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
