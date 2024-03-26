// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";

struct AcceptedRequestsExecutionEpoch {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    uint256[][][] tranchePriorityDepositsAccepted;
    uint256[] acceptedPriorityWithdrawalAmounts;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

abstract contract AcceptedRequestsExecution is IAcceptedRequestsExecution {
    // epochId => AcceptedRequestsExecutionEpoch
    mapping(uint256 => AcceptedRequestsExecutionEpoch) public acceptedRequestsExecutionPerEpoch;

    function registerAcceptedRequestExecution(
        uint256 targetEpoch,
        PendingDeposits calldata pendingDeposits,
        PendingWithdrawals calldata pendingWithdrawals,
        uint256[][][] memory tranchePriorityDepositsAccepted,
        uint256[] calldata acceptedPriorityWithdrawalAmounts
    ) external {
        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) {
            revert AcceptedRequestsExecutionAlreadyInitialised(targetEpoch);
        }
        // TODO: validate arguments ?
        acceptedRequestsExecutionPerEpoch[targetEpoch].pendingDeposits = pendingDeposits;
        acceptedRequestsExecutionPerEpoch[targetEpoch].pendingWithdrawals = pendingWithdrawals;

        acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted = tranchePriorityDepositsAccepted;

        acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts =
            acceptedPriorityWithdrawalAmounts;

        uint256 totalPendingRequests = _getTotalPendingRequests();

        if (totalPendingRequests == 0) {
            acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = 0;
        } else {
            acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = totalPendingRequests - 1;
        }

        acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.PENDING;
    }

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        if (!_isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert AcceptedRequestsExecutionAlreadyProcessed(targetEpoch);
        }

        uint256 nextIndexToProcess = acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess;

        if (nextIndexToProcess == 0) {
            acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
            return;
        }

        if (batchSize == 0) {
            revert BatchSizeShouldNotBeZero();
        }

        // calculate current transaction userRequest indexes
        uint256 startingIndexInclusive = nextIndexToProcess;

        // TODO: add check for batch size > 0
        uint256 batchSizeIndex = batchSize - 1;
        uint256 endingIndexInclusive =
            startingIndexInclusive >= batchSizeIndex ? startingIndexInclusive - batchSizeIndex : 0;

        // internal loop current transaction userRequest
        uint256 i = startingIndexInclusive;
        while (i >= endingIndexInclusive) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);

            if (isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current epoch
                if (depositNftDetails.epochId <= targetEpoch) {
                    // instructions of how this request deposit will be accepted in different tranches
                    uint256 requestTrancheIndex = _getTrancheIndex(depositNftDetails.tranche);
                    uint256[] memory trancheDepositAcceptedAmounts = acceptedRequestsExecutionPerEpoch[targetEpoch]
                        .tranchePriorityDepositsAccepted[requestTrancheIndex][depositNftDetails.priority];

                    // loop through the target tranches that the deposit request will accepted
                    // accepted tranche index is always same or greater than the request tranche index
                    for (
                        uint256 targetTrancheIndex = requestTrancheIndex;
                        targetTrancheIndex < trancheDepositAcceptedAmounts.length;
                        ++targetTrancheIndex
                    ) {
                        uint256 totalAcceptedAmount = trancheDepositAcceptedAmounts[targetTrancheIndex];
                        if (totalAcceptedAmount == 0) continue;

                        uint256 totalTranchePriorityDepositedAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                            .pendingDeposits
                            .tranchePriorityDepositsAmounts[requestTrancheIndex][depositNftDetails.priority];

                        // calculate the amount that will be accepted in this tranche
                        if (totalTranchePriorityDepositedAmount > 0) {
                            uint256 userAcceptedDepositAmount = totalAcceptedAmount * depositNftDetails.assetAmount
                                / totalTranchePriorityDepositedAmount;
                            _acceptDepositRequest(
                                userRequestNftId, _getTranche(targetTrancheIndex), userAcceptedDepositAmount
                            );
                        }
                    }

                    // whatever is not accepted will be rejected, deposit requests are not carried in next epochs
                    if (trancheDepositNftDetails(userRequestNftId).assetAmount > 0) {
                        _rejectDepositRequest(userRequestNftId);
                    }
                }
            } else {
                // ### Withdrawal Requests Processing ###
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);

                // only consider all past withdrawal requests
                if (withdrawalNftDetails.epochId <= targetEpoch) {
                    // instructions of how this request withdrawal will be accepted in different tranches
                    uint256 totalAcceptedAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                        .acceptedPriorityWithdrawalAmounts[withdrawalNftDetails.priority];
                    if (totalAcceptedAmount > 0) {
                        uint256 totalWithdrawalAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                            .pendingWithdrawals
                            .priorityWithdrawalAmounts[withdrawalNftDetails.priority];

                        // calculate the amount withdrawn that will be accepted in this tranche
                        if (totalWithdrawalAmount > 0) {
                            uint256 acceptedWithdrawalShares =
                                withdrawalNftDetails.sharesAmount * totalAcceptedAmount / totalWithdrawalAmount;

                            _acceptWithdrawalRequest(userRequestNftId, acceptedWithdrawalShares);
                        }
                    }
                }
            }

            if (i == 0) {
                acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
                break;
            }

            unchecked {
                --i;
            }
        }

        acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = i;
    }

    function acceptedRequestsExecutionPerEpochStatus(uint256 targetEpoch) external view returns (TaskStatus) {
        return acceptedRequestsExecutionPerEpoch[targetEpoch].status;
    }

    //*** Virtual Methods ***/

    // ERC721
    function _getTotalPendingRequests() internal view virtual returns (uint256);

    function _getPendingRequestIdByIndex(uint256 index) internal view virtual returns (uint256);

    function _getPendingRequestOwner(uint256 tokenId) internal view virtual returns (address);

    // Pending Pool
    function isDepositNft(uint256 nftId) public pure virtual returns (bool);

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

    function decomposeWithdrawalId(uint256 id) public pure virtual returns (address tranche, uint256 withdrawalId);

    function _isClearingTime() internal view virtual returns (bool);

    function _getTrancheIndex(address tranche) internal view virtual returns (uint256);

    function _getTranche(uint256 index) internal view virtual returns (address);

    function _acceptDepositRequest(uint256 dNftID, address tranche, uint256 acceptedAmount) internal virtual;

    function _rejectDepositRequest(uint256 dNftID) internal virtual;

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal virtual;
}
