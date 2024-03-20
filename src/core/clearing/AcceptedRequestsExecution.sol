// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../../shared/CommonErrors.sol";

struct AcceptedRequestsExecutionEpoch {
    uint256[][][] tranchePriorityDepositsAccepted;
    uint256[] acceptedPriorityWithdrawalAmounts;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

abstract contract AcceptedRequestsExecution is IAcceptedRequestsExecution {
    // epochId => AcceptedRequestsExecutionEpoch
    mapping(uint256 => AcceptedRequestsExecutionEpoch) public acceptedRequestsExecutionPerEpoch;
    // epochId => requested tranche => priority => accepted tranche => ratios
    mapping(uint256 => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256 ratios)))) public
        acceptedDepositsRatios;

    function registerAcceptedRequestExecution(
        uint256 targetEpoch,
        PendingDeposits memory pendingDeposits,
        PendingWithdrawals memory pendingWithdrawals,
        uint256[][][] memory tranchePriorityDepositsAccepted,
        uint256[] memory acceptedPriorityWithdrawalAmounts
    ) external {
        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status != TaskStatus.UNINITIALISED) {
            revert AcceptedRequestsExecutionAlreadyInitialised(targetEpoch);
        }
        // TODO: validate arguments

        // calculate and store accepted deposits ratios
        for (
            uint256 requestedTranche = 0; requestedTranche < tranchePriorityDepositsAccepted.length; ++requestedTranche
        ) {
            for (uint256 priority = 0; priority < tranchePriorityDepositsAccepted[requestedTranche].length; ++priority)
            {
                for (
                    uint256 acceptedTranche = 0;
                    acceptedTranche < tranchePriorityDepositsAccepted[requestedTranche][priority].length;
                    ++acceptedTranche
                ) {
                    acceptedDepositsRatios[targetEpoch][requestedTranche][priority][acceptedTranche] =
                    tranchePriorityDepositsAccepted[requestedTranche][priority][acceptedTranche]
                        / pendingDeposits.tranchePriorityDepositsAmounts[requestedTranche][priority];
                }
            }
        }
        acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted = tranchePriorityDepositsAccepted;
        acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts =
            acceptedPriorityWithdrawalAmounts;
        acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.PENDING;
    }

    function executeAcceptedRequestsBatch(uint256 targetEpoch, uint256 batchSize) external {
        if (!_isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (acceptedRequestsExecutionPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert AcceptedRequestsExecutionAlreadyProcessed(targetEpoch);
        }

        // internal loop from current tranche index to last
        for (uint256 i = _getTotalPendingRequests() - 1; i >= 0; ++i) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);
            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                if (depositNftDetails.epochId != targetEpoch) break;
                (address trancheAddress, uint256 depositId) = decomposeDepositId(userRequestNftId);
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                if (withdrawalNftDetails.epochId > targetEpoch) break;
                (address trancheAddress, uint256 withdrawalId) = decomposeWithdrawalId(userRequestNftId);
            }
        }
    }

    //*** Helper Methods ***/

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

    function _isClearingTime() internal view virtual returns (bool);
}
