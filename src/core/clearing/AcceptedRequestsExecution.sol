// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IAcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

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

        // copy tranchePriorityDepositsAccepted to storage
        acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted =
            new uint256[][][](tranchePriorityDepositsAccepted.length);
        for (uint256 i = 0; i < tranchePriorityDepositsAccepted.length; ++i) {
            acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted[i] =
                new uint256[][](tranchePriorityDepositsAccepted[i].length);
            for (uint256 j = 0; j < tranchePriorityDepositsAccepted[i].length; ++j) {
                acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted[i][j] =
                    new uint256[](tranchePriorityDepositsAccepted[i][j].length);
                for (uint256 k = 0; k < tranchePriorityDepositsAccepted[i][j].length; ++k) {
                    acceptedRequestsExecutionPerEpoch[targetEpoch].tranchePriorityDepositsAccepted[i][j][k] =
                        tranchePriorityDepositsAccepted[i][j][k];
                }
            }
        }

        acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts =
            acceptedPriorityWithdrawalAmounts;

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
        uint256 batchSizeIndex = batchSize - 1;
        uint256 endingIndexInclusive =
            startingIndexInclusive >= batchSizeIndex ? startingIndexInclusive - batchSizeIndex : 0;

        // internal loop from current tranche index to last
        uint256 i = startingIndexInclusive;
        while (i >= endingIndexInclusive) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);

            if (isDepositNft(userRequestNftId)) {
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);
                if (depositNftDetails.epochId != targetEpoch) break;

                uint256[] storage trancheDepositAcceptedAmounts = acceptedRequestsExecutionPerEpoch[targetEpoch]
                    .tranchePriorityDepositsAccepted[_getTrancheIndex(depositNftDetails.tranche)][depositNftDetails.priority];

                uint256 depositNftTotalAmountAccepted = 0;

                console2.log(
                    "requested deposit:",
                    _getPendingRequestOwner(userRequestNftId),
                    string.concat(
                        " ",
                        Strings.toString(_getTrancheIndex(depositNftDetails.tranche)),
                        " ",
                        Strings.toString(depositNftDetails.priority),
                        " ",
                        Strings.toString(depositNftDetails.assetAmount)
                    )
                );
                for (
                    uint256 targetTrancheIndex = 0;
                    targetTrancheIndex < trancheDepositAcceptedAmounts.length;
                    ++targetTrancheIndex
                ) {
                    uint256 totalAcceptedAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                        .tranchePriorityDepositsAccepted[_getTrancheIndex(depositNftDetails.tranche)][depositNftDetails
                        .priority][targetTrancheIndex];
                    uint256 totalTranchePriorityDepositedAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                        .pendingDeposits
                        .tranchePriorityDepositsAmounts[_getTrancheIndex(depositNftDetails.tranche)][depositNftDetails
                        .priority];

                    uint256 userAcceptedDepositAmount = totalTranchePriorityDepositedAmount == 0
                        ? 0
                        : totalAcceptedAmount * depositNftDetails.assetAmount / totalTranchePriorityDepositedAmount;

                    console2.log(
                        string.concat(
                            Strings.toString(_getTrancheIndex(depositNftDetails.tranche)),
                            Strings.toString(depositNftDetails.priority),
                            Strings.toString(targetTrancheIndex)
                        ),
                        string.concat(
                            Strings.toString(totalAcceptedAmount),
                            " ",
                            Strings.toString(totalTranchePriorityDepositedAmount),
                            " ",
                            Strings.toString(userAcceptedDepositAmount)
                        )
                    );
                    if (userAcceptedDepositAmount != 0) {
                        console2.log("accepted");
                        _acceptDepositRequest(
                            userRequestNftId, _getTranche(targetTrancheIndex), userAcceptedDepositAmount
                        );
                        depositNftTotalAmountAccepted += userAcceptedDepositAmount;
                    }
                }

                if (depositNftTotalAmountAccepted < depositNftDetails.assetAmount) {
                    console2.log("rejected");
                    _rejectDepositRequest(userRequestNftId);
                }
            } else {
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);
                if (withdrawalNftDetails.epochId > targetEpoch) break;

                uint256[] storage targetPriorityWithdrawAmounts =
                    acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts;

                (address trancheAddress,) = decomposeWithdrawalId(userRequestNftId);

                for (
                    uint256 targetPriorityIndex = 0;
                    targetPriorityIndex < targetPriorityWithdrawAmounts.length;
                    ++targetPriorityIndex
                ) {
                    uint256 withdrawalAmount =
                        ILendingPoolTranche(trancheAddress).convertToAssets(withdrawalNftDetails.sharesAmount);

                    uint256 totalAcceptedAmount = targetPriorityWithdrawAmounts[targetPriorityIndex];
                    uint256 totalDepositedAmount = acceptedRequestsExecutionPerEpoch[targetEpoch]
                        .pendingWithdrawals
                        .priorityWithdrawalAmounts[targetPriorityIndex];

                    uint256 acceptedWithdrawalAmount =
                        totalDepositedAmount == 0 ? 0 : totalAcceptedAmount * withdrawalAmount / totalDepositedAmount;

                    if (acceptedWithdrawalAmount != 0) {
                        _acceptWithdrawalRequest(userRequestNftId, acceptedWithdrawalAmount);
                    }
                }
            }

            if (i >= endingIndexInclusive) {
                if (i == 0) {
                    acceptedRequestsExecutionPerEpoch[targetEpoch].status = TaskStatus.ENDED;
                    break;
                }
                --i;
                acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = i;
            }
        }
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
