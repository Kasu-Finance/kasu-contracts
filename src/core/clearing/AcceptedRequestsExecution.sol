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
    mapping(uint256 => AcceptedRequestsExecutionEpoch) private _acceptedRequestsExecutionPerEpoch;

    /* ========== EXTERNAL VIEW FUNCTION ========== */

    function acceptedRequestsExecutionPerEpochStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return _acceptedRequestsExecutionPerEpoch[targetEpoch].status;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        _onlyClearingCoordinator();

        if (_acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.UNINITIALIZED) {
            _initializeAcceptedRequests(targetEpoch);

            // if there are no pending requests, we can skip the processing
            if (_acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
                return;
            }
        } else if (_acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert AcceptedRequestsExecutionAlreadyProcessed(targetEpoch);
        }

        if (batchSize == 0) {
            return;
        }

        uint256 nextIndexToProcess = _acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess;

        uint256 endingIndexInclusive;
        if (batchSize <= nextIndexToProcess) {
            unchecked {
                endingIndexInclusive = nextIndexToProcess - (batchSize - 1);
            }
        }

        address[] memory tranches = _lendingPoolTranches();

        // loop from the last index on and process the requests
        uint256 i = nextIndexToProcess;
        while (i >= endingIndexInclusive) {
            uint256 userRequestNftId = _pendingRequestIdByIndex(i);

            if (UserRequestIds.isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current and past epochs
                if (depositNftDetails.epochId <= targetEpoch) {
                    // instructions of how this request deposit will be accepted in different tranches
                    uint256 requestTrancheIndex = _trancheIndex(tranches, depositNftDetails.tranche);
                    uint256[] memory trancheDepositAcceptedAmounts =
                        _tranchePriorityDepositsAccepted(targetEpoch)[requestTrancheIndex][depositNftDetails.priority];

                    // loop through the target tranches that the deposit request will accepted
                    // accepted tranche index is always same or greater than the request tranche index

                    uint256 requestAmountLeft = depositNftDetails.assetAmount;
                    for (
                        uint256 trancheIndex = requestTrancheIndex;
                        trancheIndex < trancheDepositAcceptedAmounts.length;
                        ++trancheIndex
                    ) {
                        uint256 totalAcceptedAmount = trancheDepositAcceptedAmounts[trancheIndex];
                        if (totalAcceptedAmount == 0) continue;

                        uint256 totalTranchePriorityDepositedAmount = _pendingDeposits(targetEpoch)
                            .tranchePriorityDepositsAmounts[requestTrancheIndex][depositNftDetails.priority];

                        // calculate the amount that will be accepted in this tranche
                        if (totalTranchePriorityDepositedAmount == totalAcceptedAmount) {
                            // in case everything is accepted, we can accept the full amount and break as there is nothing left to accept
                            _acceptDepositRequest(
                                userRequestNftId, _trancheAddress(tranches, trancheIndex), depositNftDetails.assetAmount
                            );
                            requestAmountLeft = 0;
                            break;
                        } else if (totalTranchePriorityDepositedAmount > 0) {
                            uint256 userAcceptedDepositAmountMultiplied =
                                totalAcceptedAmount * depositNftDetails.assetAmount;
                            uint256 userAcceptedDepositAmount =
                                userAcceptedDepositAmountMultiplied / totalTranchePriorityDepositedAmount;

                            // round up the amount if there is a remainder, so that we're sure we're accepting at least the total accepted amount
                            if (userAcceptedDepositAmount < requestAmountLeft) {
                                if (userAcceptedDepositAmountMultiplied % totalTranchePriorityDepositedAmount > 0) {
                                    unchecked {
                                        userAcceptedDepositAmount++;
                                    }
                                }
                            } else if (userAcceptedDepositAmount > requestAmountLeft) {
                                // if we're accepting more than the request amount (because we've rounded up in the previous tranches), we need to adjust the amount to the request amount
                                userAcceptedDepositAmount = requestAmountLeft;
                            }

                            _acceptDepositRequest(
                                userRequestNftId, _trancheAddress(tranches, trancheIndex), userAcceptedDepositAmount
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
                        _acceptedPriorityWithdrawalAmounts(targetEpoch)[withdrawalNftDetails.priority];
                    if (totalAcceptedAmount > 0) {
                        uint256 totalWithdrawalAmount =
                            _pendingWithdrawals(targetEpoch).priorityWithdrawalAmounts[withdrawalNftDetails.priority];

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
                _acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
                break;
            }

            unchecked {
                --i;
            }
        }

        _acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = i;
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _initializeAcceptedRequests(uint256 targetEpoch) private {
        uint256 totalPendingRequests = _clearingDataStorage(targetEpoch).totalPendingRequestsToProcess;

        if (totalPendingRequests == 0) {
            _acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        } else {
            unchecked {
                _acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = totalPendingRequests - 1;
            }
            _acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.PENDING;
        }
    }

    /* ========== VIRTUAL METHODS ========== */

    // ERC721
    function _totalPendingRequests() internal view virtual returns (uint256);

    function _pendingRequestIdByIndex(uint256 index) internal view virtual returns (uint256);

    function _pendingRequestOwner(uint256 tokenId) internal view virtual returns (address);

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

    function _lendingPoolTranches() internal view virtual returns (address[] memory);

    function _trancheIndex(address[] memory tranches, address tranche) internal view virtual returns (uint256);

    function _trancheAddress(address[] memory tranches, uint256 index) internal view virtual returns (address);

    function _acceptDepositRequest(uint256 dNftID, address tranche, uint256 acceptedAmount) internal virtual;

    function _rejectDepositRequest(uint256 dNftID) internal virtual;

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal virtual;

    // Clearing Steps
    function _pendingDeposits(uint256 epoch) internal view virtual returns (PendingDeposits memory);

    function _pendingWithdrawals(uint256 epoch) internal view virtual returns (PendingWithdrawals memory);

    function _tranchePriorityDepositsAccepted(uint256 epoch) internal view virtual returns (uint256[][][] memory);

    function _acceptedPriorityWithdrawalAmounts(uint256 epoch) internal view virtual returns (uint256[] memory);

    function _clearingDataStorage(uint256 epoch) internal view virtual returns (ClearingData storage);

    function _onlyClearingCoordinator() internal view virtual;
}
