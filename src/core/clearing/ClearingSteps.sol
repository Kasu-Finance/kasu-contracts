// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./PendingRequestsPriorityCalculation.sol";
import "./AcceptedRequestsCalculation.sol";
import "../interfaces/clearing/IClearingSteps.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import {AcceptedRequestsExecution} from "./AcceptedRequestsExecution.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../../shared/AddressLib.sol";

/**
 * @title Clearing steps contract
 * @notice Contract for lending pool clearing storage and execution.
 * @dev
 * All external functions are called by the clearing coordinator contract.
 * Clearing steps 2, 3 and 4 are executed via this contract.
 * Step 2 uses the PendingRequestsPriorityCalculation contract to calculate the priority of each pending requests.
 * Step 3 uses the AcceptedRequestsCalculation contract to calculate the accepted deposit and withdrawal request amounts.
 * Step 4 uses the AcceptedRequestsExecution contract to process the accepted deposit and withdrawal requests.
 * Clearing step 2 and 4 require looping over user pending requests.
 * This is why PendingPool extends ClearingSteps and implements abstract functions from this contract,
 * so we can access the pending requests storage directly.
 */
abstract contract ClearingSteps is IClearingSteps, PendingRequestsPriorityCalculation, AcceptedRequestsExecution {
    /// @notice Clearing coordinator contract.
    IClearingCoordinator internal immutable _clearingCoordinator;
    /// @notice Accepted requests calculation contract.
    /// @dev This contract is used for step 3 of the clearing process.
    IAcceptedRequestsCalculation private immutable _acceptedRequestsCalculation;

    /// @dev Lending pool clearing data per epoch.
    mapping(uint256 => ClearingData) private _clearingDataPerEpoch;

    /**
     * @notice Constructor.
     * @param clearingCoordinator_ Clearing coordinator contract.
     * @param acceptedRequestsCalculation_ Accepted requests calculation contract.
     */
    constructor(IClearingCoordinator clearingCoordinator_, IAcceptedRequestsCalculation acceptedRequestsCalculation_) {
        AddressLib.checkIfZero(address(clearingCoordinator_));
        AddressLib.checkIfZero(address(acceptedRequestsCalculation_));

        _clearingCoordinator = clearingCoordinator_;
        _acceptedRequestsCalculation = acceptedRequestsCalculation_;
    }

    // Getters

    /**
     * @notice Get the pending deposit amounts for the epoch.
     * @param epoch Epoch number.
     * @return Pending deposit amounts.
     */
    function pendingDeposits(uint256 epoch) external view returns (PendingDeposits memory) {
        return _pendingDeposits(epoch);
    }

    /**
     * @notice Get the pending withdrawal amounts for the epoch.
     * @param epoch Epoch number.
     * @return Pending withdrawal amounts.
     */
    function pendingWithdrawals(uint256 epoch) external view returns (PendingWithdrawals memory) {
        return _pendingWithdrawals(epoch);
    }

    /**
     * @notice Get the accepted deposit and withdrawal amounts for the epoch.
     * @param epoch Epoch number.
     * @return Accepted deposit amounts.
     * @return Accepted withdrawal amounts.
     */
    function getClearingAcceptedAmounts(uint256 epoch) external view returns (uint256[][][] memory, uint256[] memory) {
        return (_tranchePriorityDepositsAccepted(epoch), _acceptedPriorityWithdrawalAmounts(epoch));
    }

    /**
     * @notice Calculate accepted request amounts and save them to the storage.
     * @dev This function can only be called by the clearing coordinator contract for step 3 of the clearing process.
     * @param config Clearing configuration.
     * @param balance Lending pool excess and owed funds.
     * @param targetEpoch Epoch number to calculate the accepted requests for.
     */
    function calculateAndSaveAcceptedRequests(
        ClearingConfiguration memory config,
        LendingPoolBalance memory balance,
        uint256 targetEpoch
    ) external {
        _onlyClearingCoordinator();

        ClearingInput memory input = ClearingInput({
            config: config,
            balance: balance,
            pendingDeposits: _pendingDeposits(targetEpoch),
            pendingWithdrawals: _pendingWithdrawals(targetEpoch)
        });

        (
            _clearingDataPerEpoch[targetEpoch].tranchePriorityDepositsAccepted,
            _clearingDataPerEpoch[targetEpoch].acceptedPriorityWithdrawalAmounts
        ) = _acceptedRequestsCalculation.calculateAcceptedRequests(input);
    }

    //*** Virtual Methods ***/

    function _pendingDeposits(uint256 epoch) internal view override returns (PendingDeposits memory) {
        return _clearingDataPerEpoch[epoch].pendingDeposits;
    }

    function _pendingWithdrawals(uint256 epoch) internal view override returns (PendingWithdrawals memory) {
        return _clearingDataPerEpoch[epoch].pendingWithdrawals;
    }

    function _tranchePriorityDepositsAccepted(uint256 epoch) internal view override returns (uint256[][][] memory) {
        return _clearingDataPerEpoch[epoch].tranchePriorityDepositsAccepted;
    }

    function _acceptedPriorityWithdrawalAmounts(uint256 epoch) internal view override returns (uint256[] memory) {
        return _clearingDataPerEpoch[epoch].acceptedPriorityWithdrawalAmounts;
    }

    /**
     * @notice Get the clearing data storage for the epoch.
     * @param epoch Epoch number.
     * @return Clearing data storage.
     */
    function _clearingData(uint256 epoch)
        internal
        view
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (ClearingData storage)
    {
        return _clearingDataPerEpoch[epoch];
    }

    /**
     * @notice Get the index of the tranche in the lending pool tranches array.
     * @dev To get tranches array, use _lendingPoolTranches() function.
     */
    function _lendingPoolTranches(address[] memory tranches, address tranche)
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

    function _onlyClearingCoordinator()
        internal
        view
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
    {
        if (msg.sender != address(_clearingCoordinator)) {
            revert ILendingPoolErrors.OnlyClearingCoordinator();
        }
    }

    /**
     * @notice Get the tranche address by index.
     * @dev To get tranches array, use _lendingPoolTranches() function.
     */
    function _tranche(address[] memory tranches, uint256 index)
        internal
        pure
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address)
    {
        return tranches[index];
    }

    //*** Common Virtual Methods ***/

    // ERC721Enumerable
    function _pendingRequestIdByIndex(uint256 index)
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256);

    function _totalPendingRequests()
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (uint256);

    function _pendingRequestOwner(uint256 tokenId)
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

    function _lendingPoolTranches()
        internal
        view
        virtual
        override(PendingRequestsPriorityCalculation, AcceptedRequestsExecution)
        returns (address[] memory);
}
