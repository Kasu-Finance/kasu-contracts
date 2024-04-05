// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";
import "./Constants.sol";
import "../shared/AddressLib.sol";

/**
 * @notice Kasu system variables contract setup structure.
 * @custom:member firstEpochStartTimestamp The timestamp of the start of the first epoch. Should be in the past.
 * @custom:member clearingPeriodLength The length of the clearing period.
 * @custom:member performanceFee The performance fee.
 * @custom:member loyaltyThresholds The loyalty level threshold percentages.
 * @custom:member defaultTrancheInterestChangeEpochDelay Default epoch delay when tranche interest rate is changed.
 * @custom:member ecosystemFeeRate The ecosystem fee percentage rate.
 * @custom:member protocolFeeRate The protocol fee percentage rate.
 */
struct SystemVariablesSetup {
    uint256 firstEpochStartTimestamp;
    uint256 clearingPeriodLength;
    uint256 performanceFee;
    uint256[] loyaltyThresholds;
    uint256 defaultTrancheInterestChangeEpochDelay;
    uint256 ecosystemFeeRate;
    uint256 protocolFeeRate;
    address protocolFeeReceiver;
}

/**
 * @notice Kasu system variables contract.
 * @dev This contract is used to store and manage global Kasu system variables.
 * It manages epoch, KSU epoch price and platform fee and other global variables.
 * Kasu epoch number always starts from 0.
 */
contract SystemVariables is ISystemVariables, KasuAccessControllable, Initializable {
    /// @notice The KSU token price contract.
    IKsuPrice public immutable ksuPrice;

    /// @notice The timestamp of the start of the first epoch.
    uint256 private constant _epochDuration = 1 weeks;

    /// @notice The timestamp of the start of the first epoch.
    uint256 private _firstEpochStartTimestamp;

    /// @notice The length of the clearing period.
    uint256 private _clearingPeriodLength;

    /// @notice The epoch number when the price was last updated.
    uint256 private _priceUpdateEpoch;

    /// @notice The price of the KSU token for the epoch.
    uint256 private _ksuTokenPrice;

    /// @notice The performance fee percentage.
    uint256 private _performanceFee;

    /// @notice The loyalty level threshold percentages.
    uint256[] private _loyaltyThresholds;

    /// @notice Flag to enable/disable users to deposits to junior tranche only if the user has rKSU.
    bool private _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU;

    /// @notice Default epoch delay when tranche interest rate is changed.
    uint256 private _defaultTrancheInterestChangeEpochDelay;

    /// @notice The maximum allowed interest rate per tranche.
    /// @dev This is to prevent Pool Manager from mistakenly setting a huge epoch interest rate.
    uint256 private _maxTrancheInterestRate;

    /// @notice The minimum tranche count per lending pool.
    uint256 private _minTrancheCountPerLendingPool;

    /// @notice The maximum tranche count per lending pool.
    uint256 private _maxTrancheCountPerLendingPool;

    /// @notice The ecosystem fee percentage rate.
    /// @dev Denominated in FULL_PERCENT.
    uint256 private _ecosystemFeeRate;

    /// @notice The protocol fee percentage rate.
    /// @dev Denominated in FULL_PERCENT.
    uint256 private _protocolFeeRate;

    /// @notice The protocol fee receiver.
    address private _protocolFeeReceiver;

    /// @notice The tranche name information.
    TrancheInfo[] public _trancheNameInfo;

    /**
     * @notice Constructor.
     * @param ksuPrice_ The KSU token price contract.
     * @param controller_ The Kasu controller contract.
     */
    constructor(IKsuPrice ksuPrice_, IKasuController controller_) KasuAccessControllable(controller_) {
        AddressLib.checkIfZero(address(ksuPrice_));
        AddressLib.checkIfZero(address(controller_));

        ksuPrice = ksuPrice_;
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract.
     * @param systemVariablesSetup The system variables setup structure.
     */
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

        _setPerformanceFee(systemVariablesSetup.performanceFee);
        _setLoyaltyThresholds(systemVariablesSetup.loyaltyThresholds);

        _updateKsuTokenPrice();

        _defaultTrancheInterestChangeEpochDelay = 4;
        _maxTrancheInterestRate = INTEREST_RATE_FULL_PERCENT / 20; // 5%
        _minTrancheCountPerLendingPool = 1;
        _maxTrancheCountPerLendingPool = 3;

        _trancheNameInfo.push(TrancheInfo("Junior Tranche", "JR"));
        _trancheNameInfo.push(TrancheInfo("Mezzanine Tranche", "MZ"));
        _trancheNameInfo.push(TrancheInfo("Senior Tranche", "SR"));

        _setFeeRates(systemVariablesSetup.ecosystemFeeRate, systemVariablesSetup.protocolFeeRate);

        _setProtocolFeeReceiver(systemVariablesSetup.protocolFeeReceiver);
    }

    // EPOCH

    /**
     * @notice Returns the current epoch number.
     * @return The current epoch number.
     */
    function getCurrentEpochNumber() public view returns (uint256) {
        if (block.timestamp < _firstEpochStartTimestamp) {
            return 0;
        }

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

    // performance fee

    /**
     * @notice Sets the performance fee.
     * @dev The performance fee is denominated in FULL_PERCENT and cannot exceed it.
     * @param performanceFee_ The new performance fee.
     */
    function setPerformanceFee(uint256 performanceFee_) external whenNotPaused onlyAdmin {
        _setPerformanceFee(performanceFee_);
    }

    function _setPerformanceFee(uint256 performanceFee_) internal {
        if (performanceFee_ > FULL_PERCENT) {
            revert InvalidConfiguration();
        }

        _performanceFee = performanceFee_;

        emit PerformanceFeeUpdated(performanceFee_);
    }

    /**
     * @notice Returns the performance fee.
     * @return The performance fee.
     */
    function performanceFee() external view returns (uint256) {
        return _performanceFee;
    }

    // LOYALTY THRESHOLDS

    /**
     * @notice Returns the loyalty thresholds.
     * @dev
     * The loyalty thresholds are denominated in FULL_PERCENT.
     * Index 0 represents loyalty level 1, and the last index is the highest loyalty level.
     * Loyalty level 0 is assumed by default and it should have 0% threshold.
     * @return The loyalty thresholds.
     */
    function loyaltyThresholds() external view returns (uint256[] memory) {
        return _loyaltyThresholds;
    }

    /**
     * @notice Sets the loyalty thresholds percentages.
     * @dev
     * The loyalty thresholds are denominated in FULL_PERCENT and values must be in ascending order.
     * Index 0 represents loyalty level 1, and the last index is the highest loyalty level.
     * If array has no elements then there is only one loyalty level.
     * @param loyaltyThresholds_ The new loyalty thresholds array.
     */
    function setLoyaltyThresholds(uint256[] memory loyaltyThresholds_) external whenNotPaused onlyAdmin {
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

        // TODO: emit event
    }

    // LENDING POOL

    /**
     * @notice Returns whether users can only deposit to junior tranches only when having rKSU.
     * @return true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around.
     */
    function getUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool) {
        return _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU;
    }

    /**
     * @notice Sets whether users are allowed to deposit to junior tranche only when the own rKSU.
     * @param value Set to true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around.
     */
    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external whenNotPaused onlyAdmin {
        _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU = value;

        // TODO: emit event
    }

    // TRANCHE

    /**
     * @notice Returns default epoch delay when tranche interest rate is changed.
     * @return The default epoch delay when tranche interest rate is changed.
     */
    function defaultTrancheInterestChangeEpochDelay() external view returns (uint256) {
        return _defaultTrancheInterestChangeEpochDelay;
    }

    /**
     * @notice Sets default epoch delay when tranche interest rate is changed.
     * @param defaultTrancheInterestChangeEpochDelay_ The new default epoch delay.
     */
    function setDefaultTrancheInterestChangeEpochDelay(uint256 defaultTrancheInterestChangeEpochDelay_)
        public
        whenNotPaused
        onlyAdmin
    {
        _defaultTrancheInterestChangeEpochDelay = defaultTrancheInterestChangeEpochDelay_;

        // TODO: emit event
    }

    /**
     * @notice Returns the maximum allowed interest rate allowed in tranche.
     * @return The maximum interest rate allowed in tranche.
     */
    function maxTrancheInterestRate() external view returns (uint256) {
        return _maxTrancheInterestRate;
    }

    /**
     * @notice Sets the maximum allowed interest rate per tranche.
     * @param maxTrancheInterestRate_ maximum allowed interest rate per tranche.
     */
    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) public whenNotPaused onlyAdmin {
        _maxTrancheInterestRate = maxTrancheInterestRate_;

        // TODO: emit event
    }

    /**
     * @notice Returns the minimum tranche count per lending pool.
     * @return The minimum tranche count per lending pool.
     */
    function minTrancheCountPerLendingPool() external view returns (uint256) {
        return _minTrancheCountPerLendingPool;
    }

    /**
     * @notice Returns the maximum tranche count per lending pool.
     * @return The maximum tranche count per lending pool.
     */
    function maxTrancheCountPerLendingPool() external view returns (uint256) {
        return _maxTrancheCountPerLendingPool;
    }

    /**
     * @notice Returns the default names and symbols for tranche.
     * @param index The index of the tranche.
     * @return The default name and symbol for tranche.
     */
    function getTrancheInfo(uint256 index) external view returns (TrancheInfo memory) {
        return _trancheNameInfo[index];
    }

    // FEES

    /**
     * @notice Returns the protocol fee rate.
     * @return ecosystemFeeRate The ecosystem fee rate.
     * @return protocolFeeRate The protocol fee rate.
     */
    function getFeeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate) {
        return (_ecosystemFeeRate, _protocolFeeRate);
    }

    /**
     * @notice Sets the split ratio for the collected fees.
     * @dev The sum of the ecosystem and protocol fee rates must be equal to FULL_PERCENT.
     * @param ecosystemFeeRate The ecosystem fee rate.
     * @param protocolFeeRate The protocol fee rate.
     */
    function setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) external whenNotPaused onlyAdmin {
        _setFeeRates(ecosystemFeeRate, protocolFeeRate);
    }

    function _setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) private {
        if (ecosystemFeeRate + protocolFeeRate != FULL_PERCENT) {
            revert InvalidConfiguration();
        }
        _ecosystemFeeRate = ecosystemFeeRate;
        _protocolFeeRate = protocolFeeRate;

        // TODO: emit event
    }

    /**
     * @notice Returns the protocol fee receiver.
     * @return The protocol fee receiver.
     */
    function getProtocolFeeReceiver() public view returns (address) {
        return _protocolFeeReceiver;
    }

    /**
     * @notice Sets the protocol fee receiver.
     * @param receiver The protocol fee receiver.
     */
    function setProtocolFeeReceiver(address receiver) public whenNotPaused onlyAdmin {
        _setProtocolFeeReceiver(receiver);
    }

    function _setProtocolFeeReceiver(address receiver) private {
        AddressLib.checkIfZero(receiver);
        _protocolFeeReceiver = receiver;

        // TODO: emit event
    }
}
