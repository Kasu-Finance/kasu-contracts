// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/ICalculatePendingRequestsPriority.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "forge-std/console2.sol";

struct PendingRequestsEpoch {
    PendingDeposits pendingDeposits;
    PendingWithdrawals pendingWithdrawals;
    uint256 processedIndexCount;
    uint256 status; //0: uninitialised, 1: started, 2:ended
}

abstract contract CalculatePendingRequestsPriority is ICalculatePendingRequestsPriority {
    IUserManager private immutable _userManager;
    ISystemVariables private immutable _systemVariables;

    mapping(uint256 => PendingRequestsEpoch) private pendingRequestsPerEpoch;

    constructor(IUserManager userManger_, ISystemVariables systemVariables_) {
        _userManager = userManger_;
        _systemVariables = systemVariables_;
    }

    function calculatePendingRequestsPriority(uint256 batchSize, uint256 targetEpoch) external {
        uint256 remainingPendingRequests = getRemainingPendingRequestsPriorityCalculation(targetEpoch);
        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 startingIndexInclusive = pendingRequestsPerEpoch[targetEpoch].processedIndexCount + 1;
        uint256 endingIndexInclusive = startingIndexInclusive + batchSize_ - 1;

        _initialisePendingRequests(targetEpoch);

        PendingDeposits storage pendingDeposits = pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
        PendingWithdrawals storage pendingWithdrawals = pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;

        uint256 loyaltyLevelCount = _getLoyaltyLevelCount();

        for (uint256 i = startingIndexInclusive; i <= endingIndexInclusive; ++i) {
            uint256 userRequestNftId = _getPendingRequestIdByIndex(i);
            address pendingRequestOwner = _getPendingRequestOwner(userRequestNftId);
            (, uint256 ownerLoyaltyLevel) = _getUserLoyaltyLevels(pendingRequestOwner);
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
                    targetEpoch - withdrawalNftDetails.epochId >= 5
                        || withdrawalNftDetails.requestedFrom == RequestedFrom.SYSTEM
                ) {
                    withdrawLoyaltyLevel = loyaltyLevelCount + 1;
                }

                ILendingPoolTranche tranche = ILendingPoolTranche(withdrawalNftDetails.tranche);
                uint256 assetAmount = tranche.convertToAssets(withdrawalNftDetails.sharesAmount);

                pendingWithdrawals.totalWithdrawalsAmount += assetAmount;
                pendingWithdrawals.priorityWithdrawalAmounts[withdrawLoyaltyLevel] += assetAmount;
            }
            pendingRequestsPerEpoch[targetEpoch].processedIndexCount = i;
        }

        if (
            pendingRequestsPerEpoch[targetEpoch].processedIndexCount >= _getCurrentEpochTotalPendingRequests()
                && pendingRequestsPerEpoch[targetEpoch].status != 2
        ) {
            pendingRequestsPerEpoch[targetEpoch].status = 2;
        }
    }

    function getRemainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        return _getCurrentEpochTotalPendingRequests() - pendingRequestsPerEpoch[targetEpoch].processedIndexCount;
    }

    function getPendingDeposits(uint256 targetEpoch) external returns (PendingDeposits memory) {
        return pendingRequestsPerEpoch[targetEpoch].pendingDeposits;
    }

    function getPendingWithdrawals(uint256 targetEpoch) external returns (PendingWithdrawals memory) {
        return pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals;
    }

    //*** Helper Methods ***/

    function _getUserLoyaltyLevels(address pendingRequestOwner)
        private
        returns (uint256 currentEpoch, uint256 loyaltyLevel)
    {
        return _userManager.getUserLoyaltyLevel(pendingRequestOwner);
    }

    function _getLoyaltyLevelCount() private returns (uint256) {
        return _systemVariables.loyaltyThresholds().length;
    }

    function _initialisePendingRequests(uint256 targetEpoch) private {
        if (pendingRequestsPerEpoch[targetEpoch].status != 0) return;

        uint256 loyaltyLevelsCount = _getLoyaltyLevelCount();

        // pending deposits
        pendingRequestsPerEpoch[targetEpoch].pendingDeposits.totalDepositAmount = 0;
        for (uint256 i = 0; i < _getTrancheCount(); ++i) {
            pendingRequestsPerEpoch[targetEpoch].pendingDeposits.trancheDepositsAmounts.push(0);
            for (uint256 j = 0; j < loyaltyLevelsCount; ++j) {
                pendingRequestsPerEpoch[targetEpoch].pendingDeposits.tranchePriorityDepositsAmounts[i].push(0);
            }
        }

        // pending withdrawals
        pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.totalWithdrawalsAmount = 0;
        // loyaltyLevelsCount + 1: forced withdrawals, withdrawals waiting >= 5 epochs
        for (uint256 i = 0; i < loyaltyLevelsCount + 1; ++i) {
            pendingRequestsPerEpoch[targetEpoch].pendingWithdrawals.priorityWithdrawalAmounts.push(0);
        }

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
