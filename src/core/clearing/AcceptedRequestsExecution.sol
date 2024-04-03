// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../lendingPool/UserRequestIds.sol";

struct AcceptedRequestsExecutionEpoch {
    uint256 nextIndexToProcess;
    TaskStatus status;
}

abstract contract AcceptedRequestsExecution is IAcceptedRequestsExecution {
    // epochId => AcceptedRequestsExecutionEpoch
    mapping(uint256 => AcceptedRequestsExecutionEpoch) public acceptedRequestsExecutionPerEpoch;

    function _initialiseAcceptedRequests(uint256 targetEpoch) private {
        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) {
            revert AcceptedRequestsExecutionAlreadyInitialised(targetEpoch);
        }

        uint256 totalPendingRequests = _getClearingData(targetEpoch).totalPendingRequestsToProcess;

        if (totalPendingRequests == 0) {
            acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        } else {
            unchecked {
                acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = totalPendingRequests - 1;
            }
            acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.PENDING;
        }
    }

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.UNINITIALISED) {
            _initialiseAcceptedRequests(targetEpoch);

            // if there are no pending requests, we can skip the processing
            if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
                return;
            }
        } else if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert AcceptedRequestsExecutionAlreadyProcessed(targetEpoch);
        }

        if (batchSize == 0) {
            return;
        }

        uint256 nextIndexToProcess = acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess;

        uint256 endingIndexInclusive;
        if (batchSize <= nextIndexToProcess) {
            unchecked {
                endingIndexInclusive = nextIndexToProcess - (batchSize - 1);
            }
        }

        // internal loop current transaction userRequest
        uint256 i = nextIndexToProcess;
        while (i >= endingIndexInclusive) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);

            if (UserRequestIds.isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current and past epochs
                if (depositNftDetails.epochId <= targetEpoch) {
                    // instructions of how this request deposit will be accepted in different tranches
                    uint256 requestTrancheIndex = _getTrancheIndex(depositNftDetails.tranche);
                    uint256[] memory trancheDepositAcceptedAmounts = _getTranchePriorityDepositsAccepted(targetEpoch)[requestTrancheIndex][depositNftDetails
                        .priority];

                    // loop through the target tranches that the deposit request will accepted
                    // accepted tranche index is always same or greater than the request tranche index

                    uint256 requestAmountLeft = depositNftDetails.assetAmount;
                    for (
                        uint256 targetTrancheIndex = requestTrancheIndex;
                        targetTrancheIndex < trancheDepositAcceptedAmounts.length;
                        ++targetTrancheIndex
                    ) {
                        uint256 totalAcceptedAmount = trancheDepositAcceptedAmounts[targetTrancheIndex];
                        if (totalAcceptedAmount == 0) continue;

                        uint256 totalTranchePriorityDepositedAmount = _getPendingDeposits(targetEpoch)
                            .tranchePriorityDepositsAmounts[requestTrancheIndex][depositNftDetails.priority];

                        // calculate the amount that will be accepted in this tranche
                        if (totalTranchePriorityDepositedAmount == totalAcceptedAmount) {
                            // in case everything is accepted, we can accept the full amount and break as there is nothing left to accept
                            _acceptDepositRequest(
                                userRequestNftId, _getTranche(targetTrancheIndex), depositNftDetails.assetAmount
                            );
                            requestAmountLeft = 0;
                            break;
                        } else if (totalTranchePriorityDepositedAmount > 0) {
                            uint256 userAcceptedDepositAmountMultiplied =
                                totalAcceptedAmount * depositNftDetails.assetAmount;
                            uint256 userAcceptedDepositAmount =
                                userAcceptedDepositAmountMultiplied / totalTranchePriorityDepositedAmount;

                            // round up the amount if there is a remainder, so that we're sure we're accepting at least the total accepted amount
                            if (userAcceptedDepositAmountMultiplied % totalTranchePriorityDepositedAmount > 0) {
                                if (userAcceptedDepositAmount < requestAmountLeft) {
                                    unchecked {
                                        userAcceptedDepositAmount++;
                                    }
                                } else if (userAcceptedDepositAmount > requestAmountLeft) {
                                    userAcceptedDepositAmount = requestAmountLeft;
                                }
                            }

                            _acceptDepositRequest(
                                userRequestNftId, _getTranche(targetTrancheIndex), userAcceptedDepositAmount
                            );

                            requestAmountLeft -= userAcceptedDepositAmount;
                        }
                    }

                    // whatever is not accepted will be rejected, deposit requests are not carried in next epochs
                    if (requestAmountLeft > 0) {
                        _rejectDepositRequest(userRequestNftId);
                    }
                }
            } else {
                // ### Withdrawal Requests Processing ###
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);

                // only consider withdrawals from current and past epochs
                if (withdrawalNftDetails.epochId <= targetEpoch) {
                    uint256 totalAcceptedAmount =
                        _getAcceptedPriorityWithdrawalAmounts(targetEpoch)[withdrawalNftDetails.priority];
                    if (totalAcceptedAmount > 0) {
                        uint256 totalWithdrawalAmount =
                            _getPendingWithdrawals(targetEpoch).priorityWithdrawalAmounts[withdrawalNftDetails.priority];

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

    function _isClearingTime() internal view virtual returns (bool);

    function _getTrancheIndex(address tranche) internal view virtual returns (uint256);

    function _getTranche(uint256 index) internal view virtual returns (address);

    function _acceptDepositRequest(uint256 dNftID, address tranche, uint256 acceptedAmount) internal virtual;

    function _rejectDepositRequest(uint256 dNftID) internal virtual;

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal virtual;

    // Clearing Steps
    function _getPendingDeposits(uint256 epoch) internal view virtual returns (PendingDeposits memory);

    function _getPendingWithdrawals(uint256 epoch) internal view virtual returns (PendingWithdrawals memory);

    function _getTranchePriorityDepositsAccepted(uint256 epoch) internal view virtual returns (uint256[][][] memory);

    function _getAcceptedPriorityWithdrawalAmounts(uint256 epoch) internal view virtual returns (uint256[] memory);

    function _getClearingData(uint256 epoch) internal view virtual returns (ClearingData storage);
}
