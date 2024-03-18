// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/ICalculatePendingRequestsPriority.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "../../shared/CommonErrors.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

struct PendingRequestsEpoch {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    // array by priority and tranche
    uint256[][] tempPriorityTrancheWithdrawalAmounts;
    uint256 nextIndexToProcess;
    uint256 status; //0: uninitialised, 1: started, 2:ended
}

abstract contract CalculatePendingRequestsPriority is Initializable, ICalculatePendingRequestsPriority {
    IUserManager private immutable _userManager;
    ISystemVariables private immutable _systemVariables;

    uint256 private REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION;

    mapping(uint256 => PendingRequestsEpoch) private pendingRequestsPerEpoch;

    constructor(IUserManager userManger_, ISystemVariables systemVariables_) {
        _userManager = userManger_;
        _systemVariables = systemVariables_;
    }

    function __CalculatePendingRequestsPriority__init() internal onlyInitializing {
        REQUEST_WITHDRAWAL_MAX_EPOCH_DURATION = 5;
    }

    function calculatePendingRequestsPriority(uint256 batchSize, uint256 targetEpoch) external {
        if (!_systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }
        if (pendingRequestsPerEpoch[targetEpoch].status == 2) {
            revert PendingRequestsPriorityCalculationAlreadyProcessed(targetEpoch);
        }

        uint256 remainingPendingRequests = getRemainingPendingRequestsPriorityCalculation(targetEpoch);
        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 startingIndexInclusive = pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;

        _initialisePendingRequests(targetEpoch);

        PendingDeposits storage pendingDeposits = pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
        PendingWithdrawals storage pendingWithdrawals = pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;

        uint256 loyaltyLevelCount = _getLoyaltyLevelCount();

        for (uint256 i = startingIndexInclusive; i <= endingIndexInclusive; ++i) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);
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

                ILendingPoolTranche tranche = ILendingPoolTranche(withdrawalNftDetails.tranche);
                // TODO: convert at the end
                uint256 assetAmount = tranche.convertToAssets(withdrawalNftDetails.sharesAmount);

                pendingWithdrawals.totalWithdrawalsAmount += assetAmount;
                pendingWithdrawals.priorityWithdrawalAmounts[withdrawLoyaltyLevel] += assetAmount;
            }
            pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess = i;
        }

        if (
            pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess >= _getCurrentEpochTotalPendingRequests()
                && pendingRequestsPerEpoch[targetEpoch].status != 2
        ) {
            pendingRequestsPerEpoch[targetEpoch].status = 2;
        }
    }

    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        return _getCurrentEpochTotalPendingRequests() - pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
    }

    function getPendingDeposits(uint256 targetEpoch) external view returns (PendingDeposits memory) {
        return pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
    }

    function getPendingWithdrawals(uint256 targetEpoch) external view returns (PendingWithdrawals memory) {
        return pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;
    }

    //*** Helper Methods ***/

    function _getUserLoyaltyLevel(address pendingRequestOwner, uint256 epoch) private view returns (uint256) {
        return _userManager.getCalculatedUserEpochLoyaltyLevel(pendingRequestOwner, epoch);
    }

    function _getLoyaltyLevelCount() private view returns (uint256) {
        return _systemVariables.loyaltyThresholds().length + 1;
    }

    function _initialisePendingRequests(uint256 targetEpoch) private {
        if (pendingRequestsPerEpoch[targetEpoch].status != 0) return;
        uint256 trancheCount = _getTrancheCount();
        uint256 loyaltyLevelsCount = _getLoyaltyLevelCount();

        // pending deposits
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.totalDepositAmount = 0;
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.trancheDepositsAmounts = new uint256[](trancheCount);
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.tranchePriorityDepositsAmounts =
            new uint256[][](trancheCount);
        for (uint256 i = 0; i < trancheCount; ++i) {
            pendingRequestsPerEpoch[targetEpoch].pendingDeposits.tranchePriorityDepositsAmounts[i] =
                new uint256[](loyaltyLevelsCount);
        }

        // pending withdrawals
        pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.totalWithdrawalsAmount = 0;
        // loyaltyLevelsCount + 1: forced withdrawals, withdrawals waiting >= 5 epochs
        pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.priorityWithdrawalAmounts =
            new uint256[](loyaltyLevelsCount + 1);

        pendingRequestsPerEpoch[targetEpoch].status = 1;
    }

    //*** Virtual Methods ***/

    // ERC721
    function _getCurrentEpochTotalPendingRequests() internal view virtual returns (uint256);

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

    function _getTrancheIndex(address tranche) internal view virtual returns (uint256);

    function _getTrancheCount() internal view virtual returns (uint256);

    function _getTranche(uint256 index) internal view virtual returns (address);
}
