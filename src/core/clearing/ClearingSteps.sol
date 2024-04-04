// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./PendingRequestsPriorityCalculation.sol";
import "./AcceptedRequestsCalculation.sol";
import "../interfaces/clearing/IClearingSteps.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import {AcceptedRequestsExecution} from "./AcceptedRequestsExecution.sol";
import "../../shared/AddressLib.sol";

abstract contract ClearingSteps is IClearingSteps, PendingRequestsPriorityCalculation, AcceptedRequestsExecution {
    IClearingCoordinator internal immutable _clearingCoordinator;
    IAcceptedRequestsCalculation private immutable _acceptedRequestsCalculation;

    mapping(uint256 => ClearingData) internal _clearingDataPerEpoch;

    constructor(IClearingCoordinator clearingCoordinator_, IAcceptedRequestsCalculation acceptedRequestsCalculation_) {
        AddressLib.checkIfZero(address(clearingCoordinator_));
        AddressLib.checkIfZero(address(acceptedRequestsCalculation_));

        _clearingCoordinator = clearingCoordinator_;
        _acceptedRequestsCalculation = acceptedRequestsCalculation_;
    }

    // Getters

    function getPendingDeposits(uint256 epoch) external view returns (PendingDeposits memory) {
        return _getPendingDeposits(epoch);
    }

    function getPendingWithdrawals(uint256 epoch) external view returns (PendingWithdrawals memory) {
        return _getPendingWithdrawals(epoch);
    }

    function getClearingAcceptedAmounts(uint256 epoch) external view returns (uint256[][][] memory, uint256[] memory) {
        return (_getTranchePriorityDepositsAccepted(epoch), _getAcceptedPriorityWithdrawalAmounts(epoch));
    }

    function _getClearingData(uint256 epoch)
        internal
        view
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (ClearingData storage)
    {
        return _clearingDataPerEpoch[epoch];
    }

    function calculateAndSaveAcceptedRequests(
        ClearingConfiguration memory config,
        LendingPoolBalance memory balance,
        uint256 targetEpoch
    ) external {
        ClearingInput memory input = ClearingInput({
            config: config,
            balance: balance,
            pendingDeposits: _getPendingDeposits(targetEpoch),
            pendingWithdrawals: _getPendingWithdrawals(targetEpoch),
            targetEpoch: targetEpoch
        });

        (
            _clearingDataPerEpoch[targetEpoch].tranchePriorityDepositsAccepted,
            _clearingDataPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts
        ) = _acceptedRequestsCalculation.calculateAcceptedRequests(input);
    }

    //*** Virtual Methods ***/
    function _getPendingDeposits(uint256 epoch) internal view override returns (PendingDeposits memory) {
        return _clearingDataPerEpoch[epoch].pendingDeposits;
    }

    function _getPendingWithdrawals(uint256 epoch) internal view override returns (PendingWithdrawals memory) {
        return _clearingDataPerEpoch[epoch].pendingWithdrawals;
    }

    function _getTranchePriorityDepositsAccepted(uint256 epoch) internal view override returns (uint256[][][] memory) {
        return _clearingDataPerEpoch[epoch].tranchePriorityDepositsAccepted;
    }

    function _getAcceptedPriorityWithdrawalAmounts(uint256 epoch) internal view override returns (uint256[] memory) {
        return _clearingDataPerEpoch[epoch].acceptedPriorityWithdrawalAmounts;
    }

    function _getTrancheIndex(address[] memory tranches, address tranche)
        internal
        pure
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256)
    {
        for (uint256 i; i < tranches.length; ++i) {
            if (tranches[i] == tranche) {
                return i;
            }
        }

        revert CannotFindTranche(tranche);
    }

    function _getTranche(address[] memory tranches, uint256 index)
        internal
        pure
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address)
    {
        return tranches[index];
    }

    //*** Common Virtual Methods ***/

    // ERC721
    function _getPendingRequestIdByIndex(uint256 index)
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256);

    function _getTotalPendingRequests()
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256);

    function _getPendingRequestOwner(uint256 tokenId)
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address);

    // Pending Pool

    function trancheDepositNftDetails(uint256 dNftId)
        public
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (DepositNftDetails memory depositNftDetails);

    function trancheWithdrawalNftDetails(uint256 wNftId)
        public
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (WithdrawalNftDetails memory withdrawalNftDetails);

    function _getLendingPoolTranches()
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address[] memory);
}
