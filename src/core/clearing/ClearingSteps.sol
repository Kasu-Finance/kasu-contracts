// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./PendingRequestsPriorityCalculation.sol";
import "./AcceptedRequestsCalculation.sol";
import "../interfaces/clearing/IClearingSteps.sol";
import {AcceptedRequestsExecution} from "./AcceptedRequestsExecution.sol";

abstract contract ClearingSteps is IClearingSteps, PendingRequestsPriorityCalculation, AcceptedRequestsExecution {
    IAcceptedRequestsCalculation private immutable _acceptedRequestsCalculation;

    mapping(uint256 => ClearingData) internal _clearingDataPerEpoch;

    constructor(IAcceptedRequestsCalculation acceptedRequestsCalculation_) {
        _acceptedRequestsCalculation = acceptedRequestsCalculation_;
    }

    function __Clearing__init() internal onlyInitializing {
        __CalculatePendingRequestsPriority__init();
    }

    // Getters

    function getPendingDeposits(uint256 epoch) public view returns (PendingDeposits memory) {
        return _clearingDataPerEpoch[epoch].pendingDeposits;
    }

    function getPendingWithdrawals(uint256 epoch) public view returns (PendingWithdrawals memory) {
        return _clearingDataPerEpoch[epoch].pendingWithdrawals;
    }

    function getTranchePriorityDepositsAccepted(uint256 epoch) public view returns (uint256[][][] memory) {
        return _clearingDataPerEpoch[epoch].tranchePriorityDepositsAccepted;
    }

    function getAcceptedPriorityWithdrawalAmounts(uint256 epoch) public view returns (uint256[] memory) {
        return _clearingDataPerEpoch[epoch].acceptedPriorityWithdrawalAmounts;
    }

    function _getClearingData(uint256 epoch) internal view override returns (ClearingData storage) {
        return _clearingDataPerEpoch[epoch];
    }

    function calculateAndSaveAcceptedRequests(ClearingInput calldata input) external {
        (uint256[][][] memory tranchePriorityDepositsAccepted, uint256[] memory acceptedPriorityWithdrawalAmounts) =
            _acceptedRequestsCalculation.calculateAcceptedRequests(input);

        _getClearingData(input.targetEpoch).tranchePriorityDepositsAccepted = tranchePriorityDepositsAccepted;
        _getClearingData(input.targetEpoch).acceptedPriorityWithdrawalAmounts = acceptedPriorityWithdrawalAmounts;
    }

    //*** Virtual Methods ***/
    function _getPendingDeposits(uint256 epoch) internal view override returns (PendingDeposits memory) {
        return getPendingDeposits(epoch);
    }

    function _getPendingWithdrawals(uint256 epoch) internal view override returns (PendingWithdrawals memory) {
        return getPendingWithdrawals(epoch);
    }

    function _getTranchePriorityDepositsAccepted(uint256 epoch) internal view override returns (uint256[][][] memory) {
        return getTranchePriorityDepositsAccepted(epoch);
    }

    function _getAcceptedPriorityWithdrawalAmounts(uint256 epoch) internal view override returns (uint256[] memory) {
        return getAcceptedPriorityWithdrawalAmounts(epoch);
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

    function _getTrancheIndex(address tranche)
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256);

    function _getTranche(uint256 index)
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address);

    function _isClearingTime()
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (bool);
}
