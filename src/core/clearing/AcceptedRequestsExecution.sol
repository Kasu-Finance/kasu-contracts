// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../lendingPool/UserRequestIds.sol";

/**
 * @notice Accepted request execution status for the epoch.
 * @custom:member nextIndexToProcess The next request index to process.
 * @custom:member status The status of the accepted requests execution task.
 */
struct AcceptedRequestsExecutionEpoch {
    uint256 nextIndexToProcess;
    TaskStatus status;
}

/**
 * @title Accepted Requests Execution contract
 * @notice Contract for executing accepted deposit and accepted withdrawal requests.
 * @dev This contract is used in step 4 of the clearing process.
 * All external functions are called by the clearing coordinator contract.
 * Clearing step 4 requires looping over user pending requests and processing them.
 * It uses the results of step 2 and 3 to determine the accepted deposit and withdrawal request amounts.
 * Deposits can be accepted to multiple tranches. Whatever is not accepted will be rejected and refunded to the user.
 * Withdrawals can be partially accepted. Whatever is not accepted will remain pending.
 */
abstract contract AcceptedRequestsExecution is IAcceptedRequestsExecution {
    /// @dev epochId => AcceptedRequestsExecutionEpoch
    mapping(uint256 => AcceptedRequestsExecutionEpoch) private _acceptedRequestsExecutionPerEpoch;

    /* ========== EXTERNAL VIEW FUNCTION ========== */

    /**
     * @notice Returns the status of the accepted requests execution task.
     * @param targetEpoch The epoch of pending user request.
     * @return The status of the accepted requests execution task.
     */
    function acceptedRequestsExecutionPerEpochStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return _acceptedRequestsExecutionPerEpoch[targetEpoch].status;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Execute accepted deposit and withdrawal requests in batches.
     * @dev This is function to process step 4 of the clearing process.
     * This function can only be called by the clearing coordinator contract.
     * Requests can be processed in batches to avoid exceeding the block gas limit.
     * Loops over a batch of pending deposit and withdrawal requests and processes them.
     * Requests are processed in reverse order as when we fully processing a request, we remove it from the list.
     * Deposits can be accepted to multiple tranches. Whatever is not accepted will be rejected and refunded to the user.
     * Withdrawals can be partially accepted. Whatever is not accepted will remain pending.
     * @param targetEpoch Target epoch number.
     * @param batchSize Number of requests to process in a batch.
     */
    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        _onlyClearingCoordinator();

        // initialize the task if it hasn't been initialized yet for the target epoch
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

        address[] memory tranches = _lendingPoolTranches();
        ClearingData memory clearingData = _clearingDataMemory(targetEpoch);

        uint256 endingIndexInclusive;
        uint256 i;
        {
            uint256 nextIndexToProcess = _acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess;
            if (batchSize <= nextIndexToProcess) {
                unchecked {
                    endingIndexInclusive = nextIndexToProcess - (batchSize - 1);
                }
            }
            i = nextIndexToProcess;
        }

        // loop from the last index on and process the requests
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
                        clearingData.tranchePriorityDepositsAccepted[requestTrancheIndex][depositNftDetails.priority];

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

                        uint256 totalTranchePriorityDepositedAmount = clearingData.pendingDeposits
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
                            uint256 userAcceptedDepositAmount = totalAcceptedAmount * depositNftDetails.assetAmount
                                / totalTranchePriorityDepositedAmount;

                            // round up the amount if there is a remainder, so that we're sure we're accepting at least the total accepted amount
                            if (userAcceptedDepositAmount < requestAmountLeft) {
                                unchecked {
                                    // "totalAcceptedAmount * depositNftDetails.assetAmount" can be unchecked as we do same operation checked just above
                                    if (
                                        totalAcceptedAmount * depositNftDetails.assetAmount
                                                % totalTranchePriorityDepositedAmount > 0
                                    ) {
                                        // can be unchecked as "if (userAcceptedDepositAmount < requestAmountLeft)" is true, so userAcceptedDepositAmount less than max uint256
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

                    // whatever is not accepted will be rejected, deposit requests are not carried to next epoch
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
                        clearingData.acceptedPriorityWithdrawalAmounts[withdrawalNftDetails.priority];
                    if (totalAcceptedAmount > 0) {
                        uint256 totalWithdrawalAmount =
                            clearingData.pendingWithdrawals.priorityWithdrawalAmounts[withdrawalNftDetails.priority];

                        // calculate the amount withdrawn that will be accepted in this tranche
                        if (totalWithdrawalAmount > 0) {
                            uint256 acceptedWithdrawalShares =
                                withdrawalNftDetails.sharesAmount * totalAcceptedAmount / totalWithdrawalAmount;

                            // prevent dust positions from being permanently stuck due to truncation to 0
                            if (acceptedWithdrawalShares == 0 && withdrawalNftDetails.sharesAmount > 0) {
                                acceptedWithdrawalShares = withdrawalNftDetails.sharesAmount;
                            }

                            _acceptWithdrawalRequest(userRequestNftId, acceptedWithdrawalShares);
                        }
                    }
                }
            }

            // if we've processed all requests, we can end the task
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
    function _clearingDataStorage(uint256 epoch) internal view virtual returns (ClearingData storage);

    function _clearingDataMemory(uint256 epoch) internal view virtual returns (ClearingData memory);

    function _onlyClearingCoordinator() internal view virtual;
}
