// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IPendingRequestsPriorityCalculation.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/ISystemVariables.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/clearing/IClearingStepsData.sol";
import "../lendingPool/UserRequestIds.sol";

/**
 * @notice Pending requests calculation helper struct
 * @custom:member tempPriorityTrancheWithdrawalShares Temporary storage for withdrawal shares per priority and tranche.
 * @custom:member nextIndexToProcess Next index to process in the pending requests array for the clearing epoch.
 * @custom:member status Task status.
 */
struct PendingRequestsEpoch {
    // array by priority and trancheIndex
    uint256[][] tempPriorityTrancheWithdrawalShares;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

/**
 * @notice Pending requests priority calculation contract
 * @dev This contract is used for step 2 of the clearing process.
 * It calculates the priority of each pending request.
 * It also partially creates the input for the accepted requests calculation (step 3) by calculating the total deposit and withdrawal amounts.
 * The deposit priority is based on the loyalty level of the user.
 * The withdrawal priority is based on the loyalty level of the user, the age of the request and if it was enforced by the system.
 *   If the withdrawal request is older than 5 epochs, it gets the highest user priority.
 *   If the withdrawal request is enforced by the system, it gets the highest priority above all other user requests.
 */
abstract contract PendingRequestsPriorityCalculation is IPendingRequestsPriorityCalculation {
    /// @dev Number of epochs after which a withdrawal request gets the highest priority.
    uint256 private constant HIGHEST_PRIORITY_WITHDRAWAL_EPOCH_AGE = 5;

    /// @dev Pending requests calculation data.
    mapping(uint256 => PendingRequestsEpoch) private _pendingRequestsPerEpoch;

    /* ========== EXTERNAL VIEW FUNCTION ========== */

    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return _pendingRequestsPerEpoch[targetEpoch].status;
    }

    function remainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        return _clearingDataStorage(targetEpoch).totalPendingRequestsToProcess
            - _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Calculates the priority of pending requests.
     * @dev
     * This is step 2 of the clearing process.
     * This function can only be called by the clearing coordinator contract.
     * Requests can be processed in batches to avoid exceeding the block gas limit.
     * Calculate the priority for every pending request in the pending pool for the target epoch or the epoch before the target epoch.
     * The deposit priority is based on the loyalty level of the user.
     * The withdrawal priority is based on the loyalty level of the user, the age of the request and if it was enforced by the system.
     *   If the withdrawal request is older than 5 epochs, it gets the highest user priority.
     *   If the withdrawal request is enforced by the system, it gets the highest priority above all other user requests.
     * Deposit requests are grouped and stored in a 2D by requested tranche and loyalty level.
     * Withdrawal requests are grouped and stored in a 1D array by priority.
     * @param batchSize Number of requests to process in a single batch. If the number is equal or higher than the remaining requests, all the remaining requests are processed.
     * @param targetEpoch Epoch for which to calculate the pending requests priority.
     */
    function calculatePendingRequestsPriorityBatch(uint256 batchSize, uint256 targetEpoch) external {
        _onlyClearingCoordinator();

        if (_pendingRequestsPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationAlreadyProcessed(targetEpoch);
        }

        _initializePendingRequests(targetEpoch);

        uint256 remainingPendingRequests = remainingPendingRequestsPriorityCalculation(targetEpoch);

        if (remainingPendingRequests == 0) {
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
            return;
        }

        if (batchSize == 0) {
            return;
        }

        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 userRequestId = _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 endIndex = userRequestId + batchSize_;

        ClearingData storage clearingData = _clearingDataStorage(targetEpoch);
        uint256[][] storage tempPriorityTrancheWithdrawalShares =
            _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares;

        uint8 loyaltyLevelCount = _loyaltyLevelCount();

        address[] memory tranches = _lendingPoolTranches();

        for (; userRequestId < endIndex; ++userRequestId) {
            uint256 userRequestNftId = _pendingRequestIdByIndex(userRequestId);
            address pendingRequestOwner = _pendingRequestOwner(userRequestNftId);

            if (UserRequestIds.isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current epoch
                if (depositNftDetails.epochId > targetEpoch) continue;

                uint256 trancheIndex = _lendingPoolTranches(tranches, depositNftDetails.tranche);

                uint8 ownerLoyaltyLevel = _userLoyaltyLevel(pendingRequestOwner, targetEpoch);

                clearingData.pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                clearingData.pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                clearingData.pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] +=
                    depositNftDetails.assetAmount;

                _setDepositRequestPriority(userRequestNftId, ownerLoyaltyLevel);
            } else {
                // ### Withdrawal Requests Processing ###
                WithdrawalNftDetails memory withdrawalNftDetails = trancheWithdrawalNftDetails(userRequestNftId);

                // only consider all past withdrawal requests
                if (withdrawalNftDetails.epochId > targetEpoch) continue;

                // set the withdrawal request priority
                uint8 withdrawLoyaltyLevel;
                if (withdrawalNftDetails.requestedFrom == RequestedFrom.SYSTEM) {
                    // we explicitly set highest priority for admin enforced withdrawals
                    withdrawLoyaltyLevel = loyaltyLevelCount;
                } else if (targetEpoch - withdrawalNftDetails.epochId >= HIGHEST_PRIORITY_WITHDRAWAL_EPOCH_AGE) {
                    // we explicitly set highest user priority to longstanding pending withdrawals and
                    withdrawLoyaltyLevel = loyaltyLevelCount - 1;
                } else {
                    // we set the user loyalty level as the priority
                    withdrawLoyaltyLevel = _userLoyaltyLevel(pendingRequestOwner, targetEpoch);
                }

                uint256 trancheIndex = _lendingPoolTranches(tranches, withdrawalNftDetails.tranche);
                tempPriorityTrancheWithdrawalShares[withdrawLoyaltyLevel][trancheIndex] +=
                    withdrawalNftDetails.sharesAmount;

                _setWithdrawalRequestPriority(userRequestNftId, withdrawLoyaltyLevel);
            }
        }

        _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess = userRequestId;

        if (
            userRequestId >= clearingData.totalPendingRequestsToProcess
                && _pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.ENDED
        ) {
            // convert pending withdrawal shares to amounts - minimize rounding errors
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
                    withdrawalPriorityAmountSum += ILendingPoolTranche(_tranche(tranches, trancheIndex)).convertToAssets(
                        tempPriorityTrancheWithdrawalShares[withdrawalPriority][trancheIndex]
                    );
                }
                clearingData.pendingWithdrawals.totalWithdrawalsAmount += withdrawalPriorityAmountSum;
                clearingData.pendingWithdrawals.priorityWithdrawalAmounts[withdrawalPriority] +=
                    withdrawalPriorityAmountSum;
            }
            // processing completed
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _initializePendingRequests(uint256 targetEpoch) private {
        if (_pendingRequestsPerEpoch[targetEpoch].status != TaskStatus.UNINITIALIZED) return;

        unchecked {
            uint256 trancheCount = _trancheCount();
            uint256 loyaltyLevelsCount = _loyaltyLevelCount();

            ClearingData storage clearingData = _clearingDataStorage(targetEpoch);

            // initialize pending deposits
            clearingData.pendingDeposits.trancheDepositsAmounts = new uint256[](trancheCount);
            clearingData.pendingDeposits.tranchePriorityDepositsAmounts = new uint256[][](trancheCount);
            for (uint256 i; i < trancheCount; ++i) {
                clearingData.pendingDeposits.tranchePriorityDepositsAmounts[i] = new uint256[](loyaltyLevelsCount);
            }

            // initialize pending withdrawals
            // extra priority: forced withdrawals
            uint256 withdrawalPriorityLevels = loyaltyLevelsCount + 1;
            clearingData.pendingWithdrawals.priorityWithdrawalAmounts = new uint256[](withdrawalPriorityLevels);

            // initialize tempPriorityTrancheWithdrawalAmounts
            _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares =
                new uint256[][](withdrawalPriorityLevels);
            for (uint256 i; i < withdrawalPriorityLevels; ++i) {
                _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares[i] =
                    new uint256[](trancheCount);
            }
        }

        _clearingDataStorage(targetEpoch).totalPendingRequestsToProcess = _totalPendingRequests();
        _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.PENDING;
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

    function _lendingPoolTranches(address[] memory tranches, address tranche) internal view virtual returns (uint256);

    function _trancheCount() internal view virtual returns (uint256);

    function _tranche(address[] memory tranches, uint256 index) internal view virtual returns (address);

    function _userLoyaltyLevel(address pendingRequestOwner, uint256 epoch) internal view virtual returns (uint8);

    function _loyaltyLevelCount() internal view virtual returns (uint8);

    function _setDepositRequestPriority(uint256 dNftId, uint8 priority) internal virtual;

    function _setWithdrawalRequestPriority(uint256 wNftId, uint8 priority) internal virtual;

    // Clearing Steps
    function _clearingDataStorage(uint256 epoch) internal view virtual returns (ClearingData storage);

    function _onlyClearingCoordinator() internal view virtual;
}
