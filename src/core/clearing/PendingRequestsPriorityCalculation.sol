// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/clearing/IPendingRequestsPriorityCalculation.sol";
import "../interfaces/clearing/IClearingStepsData.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../lendingPool/UserRequestIds.sol";

/**
 * @notice Pending requests calculation helper per epoch.
 * @custom:member tempPriorityTrancheWithdrawalShares Temporary storage for withdrawal shares per priority and tranche.
 * @custom:member nextIndexToProcess Next index to process in the pending requests array for the clearing epoch.
 * @custom:member status Stat of the pending requests calculation.
 */
struct PendingRequestsEpoch {
    // array by priority and trancheIndex
    uint256[][] tempPriorityTrancheWithdrawalShares;
    uint256 nextIndexToProcess;
    TaskStatus status;
}

/**
 * @title Pending requests priority calculation contract
 * @notice Pending requests priority calculation contract.
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

    /**
     * @notice Get the status of the pending requests priority calculation for the target epoch.
     * @param targetEpoch Epoch for which to get the pending requests priority calculation status.
     * @return Task status.
     */
    function pendingRequestsPriorityCalculationStatus(uint256 targetEpoch) public view returns (TaskStatus) {
        return _pendingRequestsPerEpoch[targetEpoch].status;
    }

    /**
     * @notice Get the remaining pending requests to process for the target epoch.
     * @param targetEpoch Epoch for which to get the remaining pending requests to process.
     * @return Remaining pending requests to process.
     */
    function remainingPendingRequestsPriorityCalculation(uint256 targetEpoch) public view returns (uint256) {
        return _clearingDataStorage(targetEpoch).totalPendingRequestsToProcess
            - _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Calculates the priority of pending requests.
     * @dev This is function to process step 2 of the clearing process.
     * This function can only be called by the clearing coordinator contract.
     * Requests can be processed in batches to avoid exceeding the block gas limit.
     * Calculate the priority for every pending request in the pending pool for the target epoch or the epoch before the target epoch.
     * The deposit priority is based on the loyalty level of the user.
     * The withdrawal priority is based on the loyalty level of the user, the age of the request and if it was enforced by the system.
     *   If the withdrawal request is older than 5 epochs, it gets the highest user priority.
     *   If the withdrawal request is enforced by the system, it gets the highest priority above all other user requests.
     * Deposit requests are grouped and stored in a 2D by requested tranche and loyalty level.
     * Withdrawal requests are grouped and stored in a 1D array by priority.
     * @param targetEpoch Epoch for which to calculate the pending requests priority.
     * @param batchSize Number of requests to process in a single batch. If the number is equal or higher than the remaining requests, all the remaining requests are processed.
     */
    function calculatePendingRequestsPriorityBatch(uint256 targetEpoch, uint256 batchSize) external {
        _onlyClearingCoordinator();

        if (_pendingRequestsPerEpoch[targetEpoch].status == TaskStatus.ENDED) {
            revert PendingRequestsPriorityCalculationAlreadyProcessed(targetEpoch);
        }

        // initialize pending requests priority calculation if not already initialized
        if (_pendingRequestsPerEpoch[targetEpoch].status == TaskStatus.UNINITIALIZED) {
            _initializePendingRequests(targetEpoch);
        }

        uint256 remainingPendingRequests = remainingPendingRequestsPriorityCalculation(targetEpoch);

        if (remainingPendingRequests == 0) {
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
            return;
        }

        if (batchSize == 0) {
            return;
        }

        // prepare variables used in processing
        ClearingData storage clearingData = _clearingDataStorage(targetEpoch);
        uint256[][] storage tempPriorityTrancheWithdrawalShares =
        _pendingRequestsPerEpoch[targetEpoch].tempPriorityTrancheWithdrawalShares;

        uint8 loyaltyLevelCount = _loyaltyLevelCount();
        address[] memory tranches = _lendingPoolTranches();

        // get the next batch of pending requests to process
        uint256 userRequestId = _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess;
        uint256 batchSize_ = remainingPendingRequests < batchSize ? remainingPendingRequests : batchSize;
        uint256 endIndex = userRequestId + batchSize_;

        for (; userRequestId < endIndex; ++userRequestId) {
            uint256 userRequestNftId = _pendingRequestIdByIndex(userRequestId);

            if (UserRequestIds.isDepositNft(userRequestNftId)) {
                // ### Deposit Requests Processing ###
                DepositNftDetails memory depositNftDetails = trancheDepositNftDetails(userRequestNftId);

                // only consider deposit requests from current epoch
                if (depositNftDetails.epochId > targetEpoch) continue;

                uint256 trancheIndex = _trancheIndex(tranches, depositNftDetails.tranche);
                uint8 ownerLoyaltyLevel = _pendingRequestOwnerLoyaltyLevel(userRequestNftId, targetEpoch);

                clearingData.pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
                clearingData.pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
                clearingData.pendingDeposits
                .tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] += depositNftDetails.assetAmount;

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
                    withdrawLoyaltyLevel = _pendingRequestOwnerLoyaltyLevel(userRequestNftId, targetEpoch);
                }

                uint256 trancheIndex = _trancheIndex(tranches, withdrawalNftDetails.tranche);
                tempPriorityTrancheWithdrawalShares[
                    withdrawLoyaltyLevel
                ][trancheIndex] += withdrawalNftDetails.sharesAmount;

                _setWithdrawalRequestPriority(userRequestNftId, withdrawLoyaltyLevel);
            }
        }

        _pendingRequestsPerEpoch[targetEpoch].nextIndexToProcess = userRequestId;

        // if all pending requests are processed, calculate the total requested withdrawal amounts per priority from the requested withdrawn shares
        if (userRequestId >= clearingData.totalPendingRequestsToProcess) {
            // convert pending withdrawal shares to amounts to minimize rounding errors
            // loop over withdrawal priorities
            for (
                uint256 withdrawalPriority;
                withdrawalPriority < tempPriorityTrancheWithdrawalShares.length;
                ++withdrawalPriority
            ) {
                // calculate the total withdrawal amount for the priority
                uint256 withdrawalPriorityAmountSum;
                // loop over tranches
                for (
                    uint256 trancheIndex;
                    trancheIndex < tempPriorityTrancheWithdrawalShares[withdrawalPriority].length;
                    ++trancheIndex
                ) {
                    withdrawalPriorityAmountSum += ILendingPoolTranche(_trancheAddress(tranches, trancheIndex))
                        .convertToAssets(tempPriorityTrancheWithdrawalShares[withdrawalPriority][trancheIndex]);
                }

                // add to total withdrawal amount
                clearingData.pendingWithdrawals.totalWithdrawalsAmount += withdrawalPriorityAmountSum;
                // store the total withdrawal amount for the priority
                clearingData.pendingWithdrawals.priorityWithdrawalAmounts[withdrawalPriority] =
                withdrawalPriorityAmountSum;
            }

            // mark processing as completed
            _pendingRequestsPerEpoch[targetEpoch].status = TaskStatus.ENDED;
        }
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Initialize the pending requests for the target epoch.
     * @param targetEpoch Epoch for which to initialize the pending requests.
     */
    function _initializePendingRequests(uint256 targetEpoch) private {
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

    function _pendingRequestOwnerLoyaltyLevel(uint256 userRequestNftId, uint256 targetEpoch)
        internal
        view
        returns (uint8)
    {
        address pendingRequestOwner = _pendingRequestOwner(userRequestNftId);
        return _userLoyaltyLevel(pendingRequestOwner, targetEpoch);
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

    function _trancheCount() internal view virtual returns (uint256);

    function _trancheAddress(address[] memory tranches, uint256 index) internal view virtual returns (address);

    function _userLoyaltyLevel(address pendingRequestOwner, uint256 epoch) internal view virtual returns (uint8);

    function _loyaltyLevelCount() internal view virtual returns (uint8);

    function _setDepositRequestPriority(uint256 dNftId, uint8 priority) internal virtual;

    function _setWithdrawalRequestPriority(uint256 wNftId, uint8 priority) internal virtual;

    // Clearing Steps
    function _clearingDataStorage(uint256 epoch) internal view virtual returns (ClearingData storage);

    function _onlyClearingCoordinator() internal view virtual;
}
