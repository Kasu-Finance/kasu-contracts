// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../interfaces/clearing/IPendingRequestsPriorityCalculation.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/clearing/IClearingStepsData.sol";
import "../lendingPool/UserRequestIds.sol";

struct PendingRequestsEpoch {
    // array by priority and trancheIndex
    uint256[][] tempPriorityTrancheWithdrawalShares;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

abstract contract PendingRequestsPriorityCalculation is IPendingRequestsPriorityCalculation {
    uint256 constant private REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION = 5;

    // epochId => PendingRequestsEpoch
    mapping(uint256 => PendingRequestsEpoch) internal _pendingRequestsPerEpoch;

    function calculatePendingRequestsPriorityBatch(uint256 batchSize, uint256 targetEpoch) external {
        if (!_isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (_pendingRequestsPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationAlreadyProcessed(targetEpoch);
        }

        if (batchSize == 0) {
            revert BatchSizeShouldNotBeZero();
        }

        _initialisePendingRequests(targetEpoch);

        uint256 remainingPendingRequests = getRemainingPendingRequestsPriorityCalculation(targetEpoch);

        if (remainingPendingRequests == 0) {
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
            return;
        }

        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 startingIndexInclusive = _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;

        PendingDeposits storage pendingDeposits = _getClearingData(targetEpoch).pendingDeposits;
        uint256[][] storage tempPriorityTrancheWithdrawalShares =
            _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares;

        uint256 loyaltyLevelCount = _getLoyaltyLevelCount();

        for (uint256 userRequestId = startingIndexInclusive; userRequestId <= endingIndexInclusive; ++userRequestId) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(userRequestId);
            address pendingRequestOwner = _getPendingRequestOwner(userRequestNftId);
            uint256 ownerLoyaltyLevel = _getUserLoyaltyLevel(pendingRequestOwner, targetEpoch);

            if (UserRequestIds.isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current epoch
                if (depositNftDetails.epochId != targetEpoch) break;

                (address trancheAddress,) = UserRequestIds.decomposeDepositId(userRequestNftId);
                uint256 trancheIndex = _getTrancheIndex(trancheAddress);

                pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] +=
                    depositNftDetails.assetAmount;

                _setDepositRequestPriority(userRequestNftId, ownerLoyaltyLevel);
            } else {
                // ### Withdrawal Requests Processing ###
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);

                // only consider all past withdrawal requests
                if (withdrawalNftDetails.epochId > targetEpoch) break;

                // we explicitly set priority for admin enforced withdrawals
                uint256 withdrawLoyaltyLevel = ownerLoyaltyLevel;
                // we explicitly set priority to longstanding pending withdrawals and
                if (targetEpoch - withdrawalNftDetails.epochId >= REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION) {
                    withdrawLoyaltyLevel = loyaltyLevelCount - 1;
                }

                if (withdrawalNftDetails.requestedFrom == RequestedFrom.SYSTEM) {
                    withdrawLoyaltyLevel = loyaltyLevelCount;
                }

                uint256 trancheIndex = _getTrancheIndex(withdrawalNftDetails.tranche);
                tempPriorityTrancheWithdrawalShares[withdrawLoyaltyLevel][trancheIndex] +=
                    withdrawalNftDetails.sharesAmount;

                _setWithdrawalRequestPriority(userRequestNftId, withdrawLoyaltyLevel);
            }

            // TODO: can be put outside of loop
            _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess = userRequestId + 1;
        }

        if (
            _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess + 1 >= _getTotalPendingRequests()
                && _pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.ENDED
        ) {
            // convert pending withdrawal shares to amounts - minimize rounding errors
            PendingWithdrawals storage pendingWithdrawals = _getClearingData(targetEpoch).pendingWithdrawals;

            for (
                uint256 withdrawalPriority;
                withdrawalPriority < tempPriorityTrancheWithdrawalShares.length;
                ++withdrawalPriority
            ) {
                uint256 withdrawalPriorityAmountSum;
                for (
                    uint256 trancheIndex;
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
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        }
    }

    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        // TODO: what happens if new deposits are added?
        return _getTotalPendingRequests() - _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
    }

    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return _pendingRequestsPerEpoch[targetEpoch].status;
    }

    //*** Helper Methods ***/

    function _initialisePendingRequests(uint256 targetEpoch) private {
        if (_pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) return;
        uint256 trancheCount = _getTrancheCount();
        uint256 loyaltyLevelsCount = _getLoyaltyLevelCount();

        ClearingData storage clearingData = _getClearingData(targetEpoch);

        // initialise pending deposits
        clearingData.pendingDeposits.trancheDepositsAmounts = new uint256[](trancheCount);
        clearingData.pendingDeposits.tranchePriorityDepositsAmounts = new uint256[][](trancheCount);
        for (uint256 i; i < trancheCount; ++i) {
            clearingData.pendingDeposits.tranchePriorityDepositsAmounts[i] =
                new uint256[](loyaltyLevelsCount);
        }

        // initialise pending withdrawals
        // extra priority: forced withdrawals
        uint256 withdrawalPriorityLevels = loyaltyLevelsCount + 1;
        clearingData.pendingWithdrawals.priorityWithdrawalAmounts =
            new uint256[](withdrawalPriorityLevels);

        // initialise tempPriorityTrancheWithdrawalAmounts
        _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares =
            new uint256[][](withdrawalPriorityLevels);
        for (uint256 i; i < withdrawalPriorityLevels; ++i) {
            _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares[i] = new uint256[](trancheCount);
        }

        _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.PENDING;
    }

    //*** Virtual Methods ***/

    // ERC721
    function _getTotalPendingRequests() internal view virtual returns (uint256);

    function _getPendingRequestIdByIndex(uint256 index) internal view virtual returns (uint256);

    function _getPendingRequestOwner(uint256 tokenId) internal view virtual returns (address);

    // Pending Pool

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

    function _setDepositRequestPriority(uint256 dNftId, uint256 priority) internal virtual;

    function _setWithdrawalRequestPriority(uint256 wNftId, uint256 priority) internal virtual;

    // Clearing Steps
    function _getClearingData(uint256 epoch) internal view virtual returns (ClearingData storage);
}
