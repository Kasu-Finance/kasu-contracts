// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IGlobalVariables.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/CommonErrors.sol";
import "../shared/Constants.sol";

/**
 * @notice Kasu global variables contract setup structure.
 * @custom:member firstEpochStartTimestamp The timestamp of the start of the first epoch. Should be in the past.
 * @custom:member clearingPeriodLength The length of the clearing period.
 * @custom:member protocolFee The protocol fee.
 */
struct GlobalVariablesSetup {
    uint256 firstEpochStartTimestamp;
    uint256 clearingPeriodLength;
    uint256 protocolFee;
}

/**
 * @notice Kasu global variables contract.
 * @dev This contract is used to store and manage Kasu global variables.
 * It stores epoch, KSU epoch price and platform fee.
 * Kasu epoch number always starts from 1.
 */
abstract contract GlobalVariables is IGlobalVariables, Initializable {
    IKsuPrice public immutable ksuPrice;

    uint256 private constant _epochDuration = 1 weeks;
    uint256 private _firstEpochStartTimestamp;
    uint256 private _clearingPeriodLength;

    uint256 private _priceUpdateEpoch;
    uint256 private _ksuTokenPrice;

    uint256 private _protocolFee;

    constructor(IKsuPrice ksuPrice_) {
        ksuPrice = ksuPrice_;
    }

    function __GlobalVariables_init(GlobalVariablesSetup memory globalVariablesSetup) internal onlyInitializing {
        if (
            globalVariablesSetup.firstEpochStartTimestamp > block.timestamp
                || globalVariablesSetup.firstEpochStartTimestamp + _epochDuration < block.timestamp
        ) {
            revert InvalidConfiguration();
        }

        if (
            globalVariablesSetup.clearingPeriodLength == 0 || globalVariablesSetup.clearingPeriodLength > _epochDuration
        ) {
            revert InvalidConfiguration();
        }

        _firstEpochStartTimestamp = globalVariablesSetup.firstEpochStartTimestamp;
        _clearingPeriodLength = globalVariablesSetup.clearingPeriodLength;

        _setProtocolFee(globalVariablesSetup.protocolFee);
    }

    // EPOCH

    /**
     * @notice Returns the current epoch number.
     * @return The current epoch number.
     */
    function getCurrentEpochNumber() public view returns (uint256) {
        unchecked {
            return (block.timestamp - _firstEpochStartTimestamp) / _epochDuration + 1;
        }
    }

    /**
     * @notice Returns the timestamp of the start of the given epoch.
     * @param epoch The epoch number.
     * @return The timestamp of the start of the given epoch.
     */
    function getEpochStartTimestamp(uint256 epoch) external view returns (uint256) {
        if (epoch == 0) {
            revert InvalidEpochNumber();
        }

        return _firstEpochStartTimestamp + (epoch - 1) * _epochDuration;
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

    // CLEARING PERIOD

    /**
     * @notice Checks if the current epoch is in the clearing period.
     * @return True if the current epoch is in the clearing period, false otherwise.
     */
    function isClearingTime() external view returns (bool) {
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
     * @notice Returns the price of the KSU token.
     * @dev The price is locked for the duration of the epoch.
     * @return The price of the KSU token.
     */
    function ksuTokenPrice() external view returns (uint256) {
        return _ksuTokenPrice;
    }

    /**
     * @notice Updates the price of the KSU token.
     * @dev This function should be called at the start of each epoch.
     */
    function updateKsuTokenPrice() external {
        if (getCurrentEpochNumber() > _priceUpdateEpoch) {
            _priceUpdateEpoch = getCurrentEpochNumber();

            _ksuTokenPrice = ksuPrice.getKsuTokenPrice();

            emit KsuTokenPriceUpdated(_priceUpdateEpoch, _ksuTokenPrice);
        }
    }

    // PROTOCOL FEE

    /**
     * @dev Sets the protocol fee.
     * @param protocolFee_ The new protocol fee.
     */
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
}
