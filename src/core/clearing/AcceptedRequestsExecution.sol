// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import {ILendingPoolManager} from "../interfaces/lendingPool/ILendingPoolManager.sol";

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
        uint256[][][] calldata tranchePriorityDepositsAccepted,
        uint256[] calldata acceptedPriorityWithdrawalAmounts
    ) external {
        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) {
            revert AcceptedRequestsExecutionAlreadyInitialised(targetEpoch);
        }
        // TODO: validate arguments ?
        acceptedRequestsExecutionPerEpoch[targetEpoch].pendingDeposits = pendingDeposits;
        acceptedRequestsExecutionPerEpoch[targetEpoch].pendingWithdrawals = pendingWithdrawals;
        acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = _getTotalPendingRequests() - 1;
        acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.PENDING;
    }

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        if (!_isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert AcceptedRequestsExecutionAlreadyProcessed(targetEpoch);
        }

        uint256 startingIndexInclusive = acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 batchSizeIndex = batchSize + 1;
        uint256 endingIndexInclusive =
            startingIndexInclusive >= batchSizeIndex ? 0 : startingIndexInclusive - batchSizeIndex;

        AcceptedRequestsExecutionEpoch storage acceptedRequestsExecution =
            acceptedRequestsExecutionPerEpoch[targetEpoch];

        // internal loop from current tranche index to last
        uint256 i = startingIndexInclusive;
        while (i >= 0) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);

            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                if (depositNftDetails.epochId != targetEpoch) break;

                uint256[] storage trancheDepositTargetAmounts = acceptedRequestsExecution
                    .tranchePriorityDepositsAccepted[_getTrancheIndex(depositNftDetails.tranche)][depositNftDetails.priority];

                uint256 depositNftTotalAmountAccepted = 0;
                for (
                    uint256 targetTrancheIndex = 0;
                    targetTrancheIndex < trancheDepositTargetAmounts.length;
                    ++targetTrancheIndex
                ) {
                    _acceptDepositRequest(
                        userRequestNftId,
                        trancheDepositTargetAmounts[targetTrancheIndex]
                            / acceptedRequestsExecution.pendingDeposits.trancheDepositsAmounts[targetTrancheIndex]
                            * depositNftDetails.assetAmount
                    );
                    depositNftTotalAmountAccepted += trancheDepositTargetAmounts[targetTrancheIndex];
                }

                if (depositNftTotalAmountAccepted < depositNftDetails.assetAmount) {
                    _rejectDepositRequest(userRequestNftId);
                }
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                if (withdrawalNftDetails.epochId > targetEpoch) break;

                uint256[] storage targetPriorityWithdrawAmounts =
                    acceptedRequestsExecution.acceptedPriorityWithdrawalAmounts;

                (address trancheAddress,) = decomposeWithdrawalId(userRequestNftId);

                for (
                    uint256 targetPriorityIndex = 0;
                    targetPriorityIndex < targetPriorityWithdrawAmounts.length;
                    ++targetPriorityIndex
                ) {
                    uint256 acceptedWithdrawalAmount =
                        ILendingPoolTranche(trancheAddress).convertToAssets(withdrawalNftDetails.sharesAmount);

                    _acceptWithdrawalRequest(
                        userRequestNftId,
                        targetPriorityWithdrawAmounts[targetPriorityIndex]
                            / acceptedRequestsExecution.pendingWithdrawals.priorityWithdrawalAmounts[targetPriorityIndex]
                            * acceptedWithdrawalAmount
                    );
                }
            }

            if (i != 0 && i >= endingIndexInclusive) --i;
        }
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

    function _acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) internal virtual;

    function _rejectDepositRequest(uint256 dNftID) internal virtual;

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal virtual;
}
