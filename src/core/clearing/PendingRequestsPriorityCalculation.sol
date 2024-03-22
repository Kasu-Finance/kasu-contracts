// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../interfaces/clearing/IPendingRequestsPriorityCalculation.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "../../shared/CommonErrors.sol";

struct PendingRequestsEpoch {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    // array by priority and trancheIndex
    uint256[][] tempPriorityTrancheWithdrawalShares;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

abstract contract PendingRequestsPriorityCalculation is Initializable, IPendingRequestsPriorityCalculation {
    uint256 internal REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION;

    // epochId => PendingRequestsEpoch
    mapping(uint256 => PendingRequestsEpoch) internal pendingRequestsPerEpoch;

    function __CalculatePendingRequestsPriority__init() internal onlyInitializing {
        REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION = 5;
    }

    function calculatePendingRequestsPriorityBatch(uint256 batchSize, uint256 targetEpoch) public {
        if (!_isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (pendingRequestsPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationAlreadyProcessed(targetEpoch);
        }

        uint256 remainingPendingRequests = getRemainingPendingRequestsPriorityCalculation(targetEpoch);
        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 startingIndexInclusive = pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;

        _initialisePendingRequests(targetEpoch);

        PendingDeposits storage pendingDeposits = pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
        uint256[][] storage tempPriorityTrancheWithdrawalShares =
            pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares;

        uint256 loyaltyLevelCount = _getLoyaltyLevelCount();

        for (uint256 userRequestId = startingIndexInclusive; userRequestId <= endingIndexInclusive; ++userRequestId) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(userRequestId);
            address pendingRequestOwner = _getPendingRequestOwner(userRequestNftId);
            uint256 ownerLoyaltyLevel = _getUserLoyaltyLevel(pendingRequestOwner, targetEpoch);
            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                if (depositNftDetails.epochId != targetEpoch) break;
                (address trancheAddress,) = decomposeDepositId(userRequestNftId);
                uint256 trancheIndex = _getTrancheIndex(trancheAddress);

                pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] +=
                    depositNftDetails.assetAmount;

                _setDepositRequestPriority(userRequestId, ownerLoyaltyLevel);
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                if (withdrawalNftDetails.epochId > targetEpoch) break;

                uint256 withdrawLoyaltyLevel = ownerLoyaltyLevel;
                if (
                    targetEpoch - withdrawalNftDetails.epochId >= REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION
                        || withdrawalNftDetails.requestedFrom == RequestedFrom.SYSTEM
                ) {
                    withdrawLoyaltyLevel = loyaltyLevelCount;
                }

                uint256 trancheIndex = _getTrancheIndex(withdrawalNftDetails.tranche);
                tempPriorityTrancheWithdrawalShares[withdrawLoyaltyLevel][trancheIndex] +=
                    withdrawalNftDetails.sharesAmount;

                _setWithdrawalRequestPriority(userRequestId, withdrawLoyaltyLevel);
            }
            pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess = userRequestId + 1;
        }

        if (
            pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess + 1 >= _getTotalPendingRequests()
                && pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.ENDED
        ) {
            // convert pending withdrawal shares to amounts - minimize rounding errors
            PendingWithdrawals storage pendingWithdrawals = pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;

            for (
                uint256 withdrawalPriority = 0;
                withdrawalPriority < tempPriorityTrancheWithdrawalShares.length;
                ++withdrawalPriority
            ) {
                uint256 withdrawalPriorityAmountSum = 0;
                for (
                    uint256 trancheIndex = 0;
                    trancheIndex < tempPriorityTrancheWithdrawalShares[withdrawalPriority].length;
                    ++trancheIndex
                ) {
                    withdrawalPriorityAmountSum += ILendingPoolTranche(_getTranche(trancheIndex)).convertToAssets(
                        tempPriorityTrancheWithdrawalShares[withdrawalPriority][trancheIndex]
                    );
                }
                pendingWithdrawals.totalWithdrawalsAmount += withdrawalPriorityAmountSum;
                pendingWithdrawals.priorityWithdrawalAmounts[withdrawalPriority] += withdrawalPriorityAmountSum;
            }
            // processing completed
            pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        }
    }

    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        return _getTotalPendingRequests() - pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
    }

    function getPendingDeposits(uint256 targetEpoch) public view returns (PendingDeposits memory) {
        if (pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationIsNotCompleted(targetEpoch);
        }
        return pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
    }

    function getPendingWithdrawals(uint256 targetEpoch) public view returns (PendingWithdrawals memory) {
        if (pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationIsNotCompleted(targetEpoch);
        }
        return pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;
    }

    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return pendingRequestsPerEpoch[targetEpoch].status;
    }

    //*** Helper Methods ***/

    function _initialisePendingRequests(uint256 targetEpoch) private {
        if (pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) return;
        uint256 trancheCount = _getTrancheCount();
        uint256 loyaltyLevelsCount = _getLoyaltyLevelCount();

        // initialise pending deposits
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.totalDepositAmount = 0;
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.trancheDepositsAmounts = new uint256[](trancheCount);
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.tranchePriorityDepositsAmounts =
            new uint256[][](trancheCount);
        for (uint256 i = 0; i < trancheCount; ++i) {
            pendingRequestsPerEpoch[targetEpoch].pendingDeposits.tranchePriorityDepositsAmounts[i] =
                new uint256[](loyaltyLevelsCount);
        }

        // initialise pending withdrawals
        // extra priority: forced withdrawals, withdrawals waiting >= 5 epochs
        uint256 withdrawalPriorityLevels = loyaltyLevelsCount + 1;
        pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.totalWithdrawalsAmount = 0;
        pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.priorityWithdrawalAmounts =
            new uint256[](withdrawalPriorityLevels);

        // initialise tempPriorityTrancheWithdrawalAmounts
        pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares =
            new uint256[][](withdrawalPriorityLevels);
        for (uint256 i = 0; i < withdrawalPriorityLevels; ++i) {
            pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares[i] = new uint256[](trancheCount);
        }

        pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.PENDING;
    }

    //*** Virtual Methods ***/

    // ERC721
    function _getTotalPendingRequests() internal view virtual returns (uint256);

    function _getPendingRequestIdByIndex(uint256 index) internal view virtual returns (uint256);

    function _getPendingRequestOwner(uint256 tokenId) internal view virtual returns (address);

    // Pending Pool
    function isDepositNft(uint256 nftId) public pure virtual returns (bool);

    function decomposeDepositId(uint256 id) public pure virtual returns (address tranche, uint256 depositId);

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

    function _getTrancheIndex(address tranche) internal view virtual returns (uint256);

    function _getTrancheCount() internal view virtual returns (uint256);

    function _getTranche(uint256 index) internal view virtual returns (address);

    function _isClearingTime() internal view virtual returns (bool);

    function _getUserLoyaltyLevel(address pendingRequestOwner, uint256 epoch) internal view virtual returns (uint256);

    function _getLoyaltyLevelCount() internal view virtual returns (uint256);

    function _setDepositRequestPriority(uint256 depositId, uint256 priority) internal virtual;

    function _setWithdrawalRequestPriority(uint256 withdrawalId, uint256 priority) internal virtual;
}
