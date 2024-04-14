// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "../Constants.sol";

/**
 * @title Accepted requests calculation contract
 * @notice Contract for calculating the accepted deposit and withdrawal amounts.
 * @dev
 * The calculation is done in 4 steps:
 * 1. Calculate the total accepted deposit and withdrawal amounts.
 * 2. Calculate the total accepted deposit amount for each tranche.
 * 3. Calculate the accepted deposit to each tranche by the tranche and priority request.
 * 4. Calculate the accepted withdrawal amounts for each priority.
 * The output of the calculation is verified at the end.
 * The calculation is done in a single function call.
 * In step 1 we check if the draw amount is less than the maximum available funds. If not, the call will revert.
 * If the tranche is oversubscribed, the excess is distributed to higher tranches according to priority.
 * Higher priority will be prioritized when accepted over lower priority.
 * If same deposit priority, when accepting to higher tranche, the higher tranche request will be prioritized.
 *   e.g. If senior priority 1 will have priority over junior priority 1 when accepting deposits to the senior tranche.
 * Withdrawals are accepted in the order of priority top down.
 * There are two outputs of this calculation:
 * 1. 3D array mapping of each tranche priority group absolute amount being accepted to each tranche.
 * - e.g. junior priority 1 deposit amount being accepted to tranche 1, tranche 2, tranche 3, etc.
 * - first index is the tranche requested deposit, second index is the priority, and third index is the tranche it got accepted to.
 * - 1D array mapping each accepted withdrawal for each priority.
 */
contract AcceptedRequestsCalculation is IAcceptedRequestsCalculation {
    struct Step1In {
        uint256 totalDepositAmount;
        uint256 totalWithdrawalsAmount;
        ClearingConfiguration config;
        LendingPoolBalance lendingPoolBalance;
    }

    struct Step1Out {
        uint256 acceptedDepositAmount;
        uint256 acceptedWithdrawalAmount;
        uint256 increasedExcessAmount;
    }

    struct Step2In {
        uint256 acceptedDepositAmount;
        uint256 increasedExcessAmount;
        uint256[] trancheDepositsAmounts;
        uint256[] trancheDesiredRatios;
    }

    struct Step2Out {
        uint256[] acceptedTrancheDepositAmounts;
    }

    struct Step3In {
        uint256[] acceptedTrancheDepositAmounts;
        uint256[][] tranchePriorityDepositsAmounts;
    }

    struct Step3Out {
        uint256[][][] tranchePriorityDepositsAccepted;
    }

    struct Step4In {
        uint256 acceptedWithdrawalAmount;
        uint256[] priorityWithdrawalAmounts;
    }

    struct Step4Out {
        uint256[] acceptedPriorityWithdrawalAmounts;
    }

    /* ========== EXTERNAL METHODS ========== */

    /**
     * @notice Calculates the accepted requested deposit and requested withdrawal amount.
     * @dev Draw amount must be less than the maximum available funds otherwise the call will revert.
     * @param input The input data for the clearing.
     * @return tranchePriorityDepositsAccepted The accepted deposits amounts to tranche for each tranche and priority. The first index is the requested tranche, the second index is the priority, and the third index is the tranche it got accepted to.
     * @return acceptedPriorityWithdrawalAmounts The accepted withdrawal amounts for each priority.
     */
    function calculateAcceptedRequests(ClearingInput memory input)
        public
        pure
        returns (
            uint256[][][] memory tranchePriorityDepositsAccepted,
            uint256[] memory acceptedPriorityWithdrawalAmounts
        )
    {
        // Step 1: calculate total deposit and total withdrawal amounts
        Step1In memory inputData1 = Step1In({
            totalDepositAmount: input.pendingDeposits.totalDepositAmount,
            totalWithdrawalsAmount: input.pendingWithdrawals.totalWithdrawalsAmount,
            config: input.config,
            lendingPoolBalance: input.balance
        });
        Step1Out memory outputData1 = _calculateDepositAndWithdrawalAmounts(inputData1);

        // Step 2: calculate total accepted deposits for each tranche
        Step2In memory inputData2 = Step2In({
            acceptedDepositAmount: outputData1.acceptedDepositAmount,
            increasedExcessAmount: outputData1.increasedExcessAmount,
            trancheDepositsAmounts: input.pendingDeposits.trancheDepositsAmounts,
            trancheDesiredRatios: input.config.trancheDesiredRatios
        });
        Step2Out memory outputData2 = _calculateAcceptedDepositAmountForEachTranche(inputData2);

        // Step 3: calculate accepted deposit to each tranche and priority request
        Step3In memory inputData3 = Step3In({
            acceptedTrancheDepositAmounts: outputData2.acceptedTrancheDepositAmounts,
            tranchePriorityDepositsAmounts: input.pendingDeposits.tranchePriorityDepositsAmounts
        });
        Step3Out memory outputData3 = _calculateAcceptedDepositToEachTrancheAndPriorityRequest(inputData3);

        // Step 4: calculate accepted withdrawal amounts for each priority
        Step4In memory inputData4 = Step4In({
            acceptedWithdrawalAmount: outputData1.acceptedWithdrawalAmount,
            priorityWithdrawalAmounts: input.pendingWithdrawals.priorityWithdrawalAmounts
        });
        Step4Out memory outputData4 = _calculateAcceptedWithdrawalAmountsForEachPriority(inputData4);

        // apply the result
        tranchePriorityDepositsAccepted = outputData3.tranchePriorityDepositsAccepted;
        acceptedPriorityWithdrawalAmounts = outputData4.acceptedPriorityWithdrawalAmounts;

        // verify the result
        _verifyResult(input, outputData1, outputData2, outputData3, outputData4);
    }

    /* ========== INTERNAL METHODS ========== */

    /**
     * @notice Calculates the total accepted pending deposits and withdrawals and draw amount.
     * @param inputData Deposit amount, withdrawal amount, lending pool balances and required lending pool configuration.
     * @return outputData Output Accepted deposit amount, accepted withdrawal amount, and increased excess amount.
     */
    function _calculateDepositAndWithdrawalAmounts(Step1In memory inputData)
        internal
        pure
        returns (Step1Out memory outputData)
    {
        // verify draw amount is less than the maximum available funds
        uint256 maximumAvailableExcess = inputData.lendingPoolBalance.excess + inputData.totalDepositAmount;

        if (maximumAvailableExcess < inputData.config.drawAmount) {
            revert DrawAmountExceedsAvailable(inputData.config.drawAmount, maximumAvailableExcess);
        }

        // calculate the new owed amount
        uint256 newOwedAmount = inputData.lendingPoolBalance.owed + inputData.config.drawAmount;

        // calculate the new maximum and minimum excess amount
        uint256 newMaxExcessAmount = newOwedAmount * inputData.config.maxExcessPercentage / FULL_PERCENT;

        // withdrawals cannot go under minimum excess, but drawing funds can
        uint256 newMinExcessAmount = newOwedAmount * inputData.config.minExcessPercentage / FULL_PERCENT;

        // calculate accepted withdrawal amount
        uint256 maxWithdrawalAmount = Math.min(inputData.lendingPoolBalance.excess, inputData.totalWithdrawalsAmount);
        uint256 maximumExcessAfterDraw = maximumAvailableExcess - inputData.config.drawAmount;
        outputData.acceptedWithdrawalAmount = maximumExcessAfterDraw <= newMinExcessAmount
            ? 0
            : Math.min(maxWithdrawalAmount, maximumExcessAfterDraw - newMinExcessAmount);

        // calculate the total accepted deposit amount
        uint256 maximumExcessAfterWithdrawal = maximumExcessAfterDraw - outputData.acceptedWithdrawalAmount;

        if (maximumExcessAfterWithdrawal < newMaxExcessAmount) {
            outputData.acceptedDepositAmount = inputData.totalDepositAmount;
        } else {
            unchecked {
                uint256 allowedExcessDiff = maximumExcessAfterWithdrawal - newMaxExcessAmount;

                if (allowedExcessDiff < inputData.totalDepositAmount) {
                    outputData.acceptedDepositAmount = inputData.totalDepositAmount - allowedExcessDiff;
                }
            }
        }

        // calculate the increased excess amount
        uint256 newExcessAmount = inputData.lendingPoolBalance.excess + outputData.acceptedDepositAmount
            - inputData.config.drawAmount - outputData.acceptedWithdrawalAmount;

        if (newExcessAmount > inputData.lendingPoolBalance.excess) {
            unchecked {
                outputData.increasedExcessAmount = newExcessAmount - inputData.lendingPoolBalance.excess;
            }
        }
    }

    /**
     * @notice Calculates the total accepted deposit amount for each tranche.
     * @dev
     * The accepted deposit amount is distributed to each tranche based on the desired ratio.
     * If previous tranche was undersubscribed, the next tranche maximum deposit is increased.
     * @param inputData The input data.
     * @return outputData Total amounts accepted for each tranche.
     */
    function _calculateAcceptedDepositAmountForEachTranche(Step2In memory inputData)
        internal
        pure
        returns (Step2Out memory outputData)
    {
        outputData.acceptedTrancheDepositAmounts = new uint256[](inputData.trancheDepositsAmounts.length);

        // increased excess can only come from the last tranche
        uint256 acceptedDepositAmountToTranches = inputData.acceptedDepositAmount - inputData.increasedExcessAmount;

        uint256 acceptedAmount;
        uint256 previousTrancheAmountLeft;
        uint256 previousTrancheAmountOversubscribed;
        for (uint256 i; i < inputData.trancheDepositsAmounts.length - 1; ++i) {
            // calculate the maximum accepted amount for the current tranche, considering any unallocated deposits left from the previous tranche
            uint256 maxTrancheAcceptedAmount = (
                acceptedDepositAmountToTranches * inputData.trancheDesiredRatios[i] / FULL_PERCENT
            ) + previousTrancheAmountLeft;

            // get deposits for the current tranche plus the deposits left from the previous tranche
            uint256 trancheDepositsAmounts = inputData.trancheDepositsAmounts[i] + previousTrancheAmountOversubscribed;

            // get minimum from requested deposits and maximum accepted amount
            outputData.acceptedTrancheDepositAmounts[i] = Math.min(trancheDepositsAmounts, maxTrancheAcceptedAmount);

            // calculate the amount left for the next tranche, if there were not enough deposits in the current tranche
            previousTrancheAmountLeft = maxTrancheAcceptedAmount - outputData.acceptedTrancheDepositAmounts[i];
            // calculate the amount oversubscribed for the next tranche, if there were too many deposits in the current tranche
            previousTrancheAmountOversubscribed = trancheDepositsAmounts - outputData.acceptedTrancheDepositAmounts[i];
            // calculate the total accepted amount of all processed tranches
            acceptedAmount += outputData.acceptedTrancheDepositAmounts[i];
        }

        // whatever accepted deposit is left goes to the last tranche
        outputData.acceptedTrancheDepositAmounts[inputData.trancheDepositsAmounts.length - 1] =
            inputData.acceptedDepositAmount - acceptedAmount;
    }

    // maps requested deposits per tranche and priority to tranches they got accepted to

    /**
     * @notice Calculates the accepted deposit to each tranche and priority request.
     * @dev
     * The accepted deposit amount is distributed to each tranche and priority based on the previous step calculations.
     * If lower tranches are oversubscribed, the excess is distributed to higher tranches according to priority.
     * Higher tranche deposit request can never be applied to lower tranches.
     * If lower tranche and higher tranche have the same priority value, higher tranche is prioritized.
     * @param inputData Accepted tranche per deposit and requested tranche priority amounts.
     * @return outputData Accepted deposit amounts for each tranche and priority.
     */
    function _calculateAcceptedDepositToEachTrancheAndPriorityRequest(Step3In memory inputData)
        internal
        pure
        returns (Step3Out memory outputData)
    {
        // init arrays
        outputData.tranchePriorityDepositsAccepted = new uint256[][][](inputData.tranchePriorityDepositsAmounts.length);
        uint256[][] memory tranchePriorityDepositsAmounts =
            new uint256[][](inputData.tranchePriorityDepositsAmounts.length);

        for (uint256 i; i < outputData.tranchePriorityDepositsAccepted.length; ++i) {
            outputData.tranchePriorityDepositsAccepted[i] =
                new uint256[][](inputData.tranchePriorityDepositsAmounts[i].length);
            tranchePriorityDepositsAmounts[i] = new uint256[](inputData.tranchePriorityDepositsAmounts[i].length);

            for (uint256 j; j < outputData.tranchePriorityDepositsAccepted[i].length; ++j) {
                outputData.tranchePriorityDepositsAccepted[i][j] =
                    new uint256[](inputData.tranchePriorityDepositsAmounts.length);
                tranchePriorityDepositsAmounts[i][j] = inputData.tranchePriorityDepositsAmounts[i][j];
            }
        }

        // calculate accepted deposits

        // iterate over the accepted tranche deposit amounts
        for (uint256 i; i < inputData.acceptedTrancheDepositAmounts.length; ++i) {
            uint256 amountLeft = inputData.acceptedTrancheDepositAmounts[i];
            // iterate over the tranche priority deposits
            for (uint256 j = tranchePriorityDepositsAmounts[i].length; j > 0; --j) {
                if (amountLeft == 0) {
                    break;
                }

                // iterate over the tranche priority deposits - also apply to lower tranches, considering the priority
                for (uint256 k = i + 1; k > 0; --k) {
                    // can be unchecked as we check all values before we perform the subtraction
                    unchecked {
                        if (tranchePriorityDepositsAmounts[k - 1][j - 1] == 0) {
                            continue;
                        }

                        if (tranchePriorityDepositsAmounts[k - 1][j - 1] < amountLeft) {
                            outputData.tranchePriorityDepositsAccepted[k - 1][j - 1][i] =
                                tranchePriorityDepositsAmounts[k - 1][j - 1];
                            amountLeft -= tranchePriorityDepositsAmounts[k - 1][j - 1];
                            tranchePriorityDepositsAmounts[k - 1][j - 1] = 0;
                        } else {
                            outputData.tranchePriorityDepositsAccepted[k - 1][j - 1][i] = amountLeft;
                            tranchePriorityDepositsAmounts[k - 1][j - 1] -= amountLeft;
                            amountLeft = 0;
                            break;
                        }
                    }
                }
            }
        }
    }

    /**
     * @notice Calculates the accepted withdrawal amounts for each priority.
     * @dev Withdrawal amounts are accepted in the order of priority top down. The tranche is not considered here.
     * @param inputData Accepted withdrawal amount and requested withdrawal amounts for each priority.
     * @return outputData Accepted withdrawal amounts for each priority.
     */
    function _calculateAcceptedWithdrawalAmountsForEachPriority(Step4In memory inputData)
        internal
        pure
        returns (Step4Out memory outputData)
    {
        outputData.acceptedPriorityWithdrawalAmounts = new uint256[](inputData.priorityWithdrawalAmounts.length);

        uint256 amountLeft = inputData.acceptedWithdrawalAmount;
        for (uint256 i = inputData.priorityWithdrawalAmounts.length; i > 0; --i) {
            // can be unchecked as we check all values before we perform the subtraction
            unchecked {
                if (inputData.priorityWithdrawalAmounts[i - 1] < amountLeft) {
                    outputData.acceptedPriorityWithdrawalAmounts[i - 1] = inputData.priorityWithdrawalAmounts[i - 1];
                    amountLeft -= inputData.priorityWithdrawalAmounts[i - 1];
                } else {
                    outputData.acceptedPriorityWithdrawalAmounts[i - 1] = amountLeft;
                    break;
                }
            }
        }
    }

    /**
     * @notice Verifies the result of the clearing calculation.
     * @dev Verifies the deposit requests are less than or equal to the accepted deposits, and the withdrawal requests are less than or equal to the accepted withdrawals.
     * @param input The input data for the clearing.
     * @param outputData1 The output data from step 1.
     * @param outputData2 The output data from step 2.
     * @param outputData3 The output data from step 3.
     * @param outputData4 The output data from step 4.
     */
    function _verifyResult(
        ClearingInput memory input,
        Step1Out memory outputData1,
        Step2Out memory outputData2,
        Step3Out memory outputData3,
        Step4Out memory outputData4
    ) internal pure {
        // VERIFY DEPOSIT RESULT
        uint256 totalAcceptedDepositAmountSum2;
        for (uint256 i; i < outputData2.acceptedTrancheDepositAmounts.length; ++i) {
            totalAcceptedDepositAmountSum2 += outputData2.acceptedTrancheDepositAmounts[i];
        }

        uint256 totalAcceptedDepositAmountSum3;
        for (uint256 i; i < outputData3.tranchePriorityDepositsAccepted.length; ++i) {
            for (uint256 j; j < outputData3.tranchePriorityDepositsAccepted[i].length; ++j) {
                uint256 totalAcceptedDepositAmountPerTranchePriority;
                // k == i is because the tranche deposits are only accepted for the same tranche or higher ones
                for (uint256 k = i; k < outputData3.tranchePriorityDepositsAccepted[i][j].length; ++k) {
                    totalAcceptedDepositAmountPerTranchePriority += outputData3.tranchePriorityDepositsAccepted[i][j][k];
                }

                totalAcceptedDepositAmountSum3 += totalAcceptedDepositAmountPerTranchePriority;

                // verify the accepted deposit for each tranche is less than or equal to the requested deposit for each tranche
                if (
                    totalAcceptedDepositAmountPerTranchePriority
                        > input.pendingDeposits.tranchePriorityDepositsAmounts[i][j]
                ) {
                    revert InvalidDepositResult();
                }
            }
        }

        // verify all accepted deposit sums are equal and that the accepted deposit is less than or equal to the total requested deposit
        if (
            outputData1.acceptedDepositAmount != totalAcceptedDepositAmountSum2
                || outputData1.acceptedDepositAmount != totalAcceptedDepositAmountSum3
                || outputData1.acceptedDepositAmount > input.pendingDeposits.totalDepositAmount
        ) {
            revert InvalidDepositResult();
        }

        // VERIFY WITHDRAWAL RESULT
        uint256 totalAcceptedWithdrawalAmountSum4;
        for (uint256 i; i < outputData4.acceptedPriorityWithdrawalAmounts.length; ++i) {
            totalAcceptedWithdrawalAmountSum4 += outputData4.acceptedPriorityWithdrawalAmounts[i];

            // verify the accepted withdrawal for each priority is less than or equal to the requested withdrawal for each priority
            if (
                outputData4.acceptedPriorityWithdrawalAmounts[i] > input.pendingWithdrawals.priorityWithdrawalAmounts[i]
            ) {
                revert InvalidWithdrawalResult();
            }
        }

        // verify all accepted withdrawal sums are equal and that the accepted withdrawal is less than or equal to the total requested withdrawal
        if (
            outputData1.acceptedWithdrawalAmount != totalAcceptedWithdrawalAmountSum4
                || outputData1.acceptedWithdrawalAmount > input.pendingWithdrawals.totalWithdrawalsAmount
        ) {
            revert InvalidWithdrawalResult();
        }

        // VERIFY ALL
        // verify there is more accepted deposit and existing excess funds, than the new withdrawal and draw amount
        if (
            input.balance.excess + outputData1.acceptedDepositAmount
                < outputData1.acceptedWithdrawalAmount + input.config.drawAmount
        ) {
            revert InvalidResult();
        }
    }
}
