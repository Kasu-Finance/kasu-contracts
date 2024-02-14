// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";
import "../shared/Constants.sol";

/**
 * @notice Kasu system variables contract setup structure.
 * @custom:member firstEpochStartTimestamp The timestamp of the start of the first epoch. Should be in the past.
 * @custom:member clearingPeriodLength The length of the clearing period.
 * @custom:member protocolFee The protocol fee.
 */
struct SystemVariablesSetup {
    uint256 firstEpochStartTimestamp;
    uint256 clearingPeriodLength;
    uint256 protocolFee;
    uint256[] loyaltyThresholds;
}

/**
 * @notice Kasu system variables contract.
 * @dev This contract is used to store and manage Kasu system variables.
 * It stores epoch, KSU epoch price and platform fee.
 * Kasu epoch number always starts from 0.
 */
contract SystemVariables is ISystemVariables, KasuAccessControllable, Initializable {
    IKsuPrice public immutable ksuPrice;

    uint256 private constant _epochDuration = 1 weeks;
    uint256 private _firstEpochStartTimestamp;
    uint256 private _clearingPeriodLength;

    uint256 private _priceUpdateEpoch;
    uint256 private _ksuTokenPrice;

    uint256 private _protocolFee;

    uint256[] private _loyaltyThresholds;

    bool private _userCanDepositToJuniorTrancheWhenHeHasRKSU;

    constructor(IKsuPrice ksuPrice_, IKasuController controller_) KasuAccessControllable(controller_) {
        ksuPrice = ksuPrice_;
        _disableInitializers();
    }

    function initialize(SystemVariablesSetup memory systemVariablesSetup) external initializer {
        if (
            systemVariablesSetup.firstEpochStartTimestamp < block.timestamp
                || systemVariablesSetup.firstEpochStartTimestamp >= block.timestamp + _epochDuration
        ) {
            revert InvalidConfiguration();
        }

        if (
            systemVariablesSetup.clearingPeriodLength == 0
                || systemVariablesSetup.clearingPeriodLength >= _epochDuration
        ) {
            revert InvalidConfiguration();
        }

        _firstEpochStartTimestamp = systemVariablesSetup.firstEpochStartTimestamp;
        _clearingPeriodLength = systemVariablesSetup.clearingPeriodLength;

        _setProtocolFee(systemVariablesSetup.protocolFee);
        _setLoyaltyThresholds(systemVariablesSetup.loyaltyThresholds);

        _updateKsuTokenPrice();
    }

    // EPOCH

    /**
     * @notice Returns the current epoch number.
     * @return The current epoch number.
     */
    function getCurrentEpochNumber() public view returns (uint256) {
        unchecked {
            return (block.timestamp - _firstEpochStartTimestamp) / _epochDuration;
        }
    }

    /**
     * @notice Returns the timestamp of the start of the given epoch.
     * @param epoch The epoch number.
     * @return The timestamp of the start of the given epoch.
     */
    function getEpochStartTimestamp(uint256 epoch) external view returns (uint256) {
        return _firstEpochStartTimestamp + epoch * _epochDuration;
    }

    /**
     * @notice Returns the duration of an epoch.
     * @return The duration of an epoch.
     */
    function getEpochDuration() external pure returns (uint256) {
        return _epochDuration;
    }

    /**
     * @notice Returns the timestamp of the start of the next epoch.
     * @return The timestamp of the start of the next epoch.
     */
    function getNextEpochStartTimestamp() public view returns (uint256) {
        return _firstEpochStartTimestamp + (getCurrentEpochNumber() + 1) * _epochDuration;
    }

    /**
     * @notice Returns the current epoch request number.
     * @dev If the current epoch is in the clearing period, the next epoch number is returned.
     * @return requestEpoch The current epoch request number.
     */
    function getCurrentRequestEpoch() external view returns (uint256 requestEpoch) {
        requestEpoch = getCurrentEpochNumber();

        if (isClearingTime()) {
            requestEpoch++;
        }
    }

    // CLEARING PERIOD

    /**
     * @notice Checks if the current epoch is in the clearing period.
     * @return True if the current epoch is in the clearing period, false otherwise.
     */
    function isClearingTime() public view returns (bool) {
        return getNextEpochStartTimestamp() - block.timestamp <= _clearingPeriodLength;
    }

    /**
     * @notice Returns the length of the clearing period.
     * @return The length of the clearing period.
     */
    function clearingPeriodLength() external view returns (uint256) {
        return _clearingPeriodLength;
    }

    // TOKEN PRICE

    /**
     * @notice Returns the price of the KSU token for the epoch.
     * @dev The price is locked for the duration of the epoch.
     * @return The epoch price of the KSU token.
     */
    function ksuEpochTokenPrice() external view returns (uint256) {
        return _ksuTokenPrice;
    }

    /**
     * @notice Returns the epoch number when the price was last updated.
     * @return The epoch number when the price was last updated.
     */
    function getPriceUpdateEpoch() external view returns (uint256) {
        return _priceUpdateEpoch;
    }

    /**
     * @notice Updates the price of the KSU token at the start of the epoch.
     * @dev This function should be called at the start of each epoch.
     */
    function updateKsuEpochTokenPrice() external {
        if (getCurrentEpochNumber() > _priceUpdateEpoch) {
            _updateKsuTokenPrice();
        }
    }

    function _updateKsuTokenPrice() internal {
        _priceUpdateEpoch = getCurrentEpochNumber();

        _ksuTokenPrice = ksuPrice.getKsuTokenPrice();

        emit KsuTokenPriceUpdated(_priceUpdateEpoch, _ksuTokenPrice);
    }

    // PROTOCOL FEE

    /**
     * @dev Sets the protocol fee.
     * @param protocolFee_ The new protocol fee.
     */
    function setProtocolFee(uint256 protocolFee_) external onlyAdmin {
        _setProtocolFee(protocolFee_);
    }

    function _setProtocolFee(uint256 protocolFee_) internal {
        if (protocolFee_ > FULL_PERCENT) {
            revert InvalidConfiguration();
        }

        _protocolFee = protocolFee_;

        emit ProtocolFeeUpdated(protocolFee_);
    }

    /**
     * @notice Returns the protocol fee.
     * @return The protocol fee.
     */
    function protocolFee() external view returns (uint256) {
        return _protocolFee;
    }

    // LOYALTY THRESHOLDS

    /**
     * @notice Returns the loyalty thresholds.
     * @return The loyalty thresholds.
     */
    function loyaltyThresholds() external view returns (uint256[] memory) {
        return _loyaltyThresholds;
    }

    /**
     * @notice Sets the loyalty thresholds.
     * @param loyaltyThresholds_ The new loyalty thresholds array.
     */
    function setLoyaltyThresholds(uint256[] memory loyaltyThresholds_) external onlyAdmin {
        if (isClearingTime()) {
            revert CannotConfigureDuringClearingPeriod();
        }

        _setLoyaltyThresholds(loyaltyThresholds_);
    }

    function _setLoyaltyThresholds(uint256[] memory loyaltyThresholds_) internal {
        if (loyaltyThresholds_.length > 10) {
            revert InvalidConfiguration();
        }

        if (loyaltyThresholds_.length > 1) {
            for (uint256 i; i < loyaltyThresholds_.length - 1; ++i) {
                if (loyaltyThresholds_[i] > loyaltyThresholds_[i + 1]) {
                    revert InvalidConfiguration();
                }
            }
        }

        _loyaltyThresholds = loyaltyThresholds_;
    }

    // LENDING POOL

    /**
     * @notice Returns whether users can deposit to junior tranches only when having rKSU.
     * @return true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around
     */
    function getUserCanDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool) {
        return _userCanDepositToJuniorTrancheWhenHeHasRKSU;
    }

    /**
     * @notice Sets whether users are allowed to deposit only when the own rKSU
     * @param value Set to true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around
     */
    function setUserCanDepositToJuniorTrancheWhenHeHasRKSU(bool value) external onlyAdmin {
        _userCanDepositToJuniorTrancheWhenHeHasRKSU = value;
    }
}
