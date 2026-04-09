// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IFeeManager.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/lendingPool/ILendingPoolManager.sol";
import "./interfaces/lendingPool/ILendingPoolErrors.sol";
import "../locking/interfaces/IKSULocking.sol";
import "../shared/access/KasuAccessControllable.sol";
import "./AssetFunctionsBase.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";

/**
 * @title FeeManager contract.
 * @notice Contract for managing and distributing platform fees.
 * @dev The fees collected are split into ecosystem and protocol fees.
 * Ecosystem fees are sent to the KSU Locking contract and distributed to rKSU holders,
 * while protocol fees are stored in the contract until claimed.
 */
contract FeeManager is IFeeManager, AssetFunctionsBase, KasuAccessControllable {
    /// @notice KSU Locking contract.
    IKSULocking private immutable _ksuLocking;
    /// @notice System variables contract.
    ISystemVariables private immutable _systemVariables;
    /// @notice Lending pool manager contract.
    ILendingPoolManager internal immutable _lendingPoolManager;

    /// @notice Total amount of protocol fees pending to be claimed.
    uint256 public totalProtocolFeeAmount;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param underlyingAsset_ Underlying asset address.
     * @param systemVariables_ System variables contract.
     * @param controller_ Access control for Kasu protocol.
     * @param ksuLocking_ KSU Locking contract.
     */
    constructor(
        address underlyingAsset_,
        ISystemVariables systemVariables_,
        IKasuController controller_,
        IKSULocking ksuLocking_,
        ILendingPoolManager lendingPoolManager_
    ) AssetFunctionsBase(underlyingAsset_) KasuAccessControllable(controller_) {
        AddressLib.checkIfZero(address(ksuLocking_));
        AddressLib.checkIfZero(address(systemVariables_));

        _ksuLocking = ksuLocking_;
        _systemVariables = systemVariables_;
        _lendingPoolManager = lendingPoolManager_;
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Transfers fee amount from the caller and emits them to the FeeManager contract.
     * @dev
     * Only the valid lending pool can call this function.
     * The fees are split into ecosystem and protocol fees.
     * Ecosystem fees are sent to the KSU Locking contract and distributed to rKSU holders,
     * while protocol fees are stored in the contract until claimed.
     * @param amount Amount of fees to emit.
     */
    function emitFees(uint256 amount) external virtual whenNotPaused {
        if (!_lendingPoolManager.isLendingPool(msg.sender)) {
            revert ILendingPoolErrors.InvalidLendingPool(msg.sender);
        }

        _transferAssetsFrom(msg.sender, address(this), amount);

        (uint256 ecosystemFeeRate,) = _systemVariables.feeRates();

        uint256 ecosystemFeeAmount = ecosystemFeeRate * amount / FULL_PERCENT;

        // If no eligible rKSU holders, redirect ecosystem fees to protocol fees
        if (_ksuLocking.eligibleRKSUForFees() > 0) {
            _approveAsset(address(_ksuLocking), ecosystemFeeAmount);
            _ksuLocking.emitFees(ecosystemFeeAmount);
        } else {
            ecosystemFeeAmount = 0;
        }

        uint256 protocolFeeAmount = amount - ecosystemFeeAmount;
        totalProtocolFeeAmount += protocolFeeAmount;

        emit FeesEmitted(msg.sender, ecosystemFeeAmount, protocolFeeAmount);
    }

    /**
     * @notice Claims the total protocol fees and transfers them to the protocol fee receiver.
     * @dev Only the protocol fee claimer role can call this function.
     */
    function claimProtocolFees() external whenNotPaused onlyRole(ROLE_PROTOCOL_FEE_CLAIMER, msg.sender) {
        address protocolFeeReceiver = _systemVariables.protocolFeeReceiver();
        uint256 totalProtocolFeeAmount_ = totalProtocolFeeAmount;

        // Reset the total unclaimed protocol fee amount.
        totalProtocolFeeAmount = 0;

        _transferAssets(protocolFeeReceiver, totalProtocolFeeAmount_);

        emit ProtocolFeesClaimed(protocolFeeReceiver, totalProtocolFeeAmount_);
    }
}
