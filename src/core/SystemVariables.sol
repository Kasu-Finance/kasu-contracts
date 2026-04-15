// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";

/**
 * @notice Kasu system variables contract setup structure.
 * @custom:member initialEpochStartTimestamp The timestamp of the start of the initial epoch. Should be in the past.
 * @custom:member clearingPeriodLength The length of the clearing period.
 * @custom:member performanceFee The performance fee.
 * @custom:member loyaltyThresholds The loyalty level threshold percentages.
 * @custom:member defaultTrancheInterestChangeEpochDelay Default epoch delay when tranche interest rate is changed.
 * @custom:member ecosystemFeeRate The ecosystem fee percentage rate.
 * @custom:member protocolFeeRate The protocol fee percentage rate.
 */
struct SystemVariablesSetup {
    uint256 initialEpochStartTimestamp;
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
 * Only Kasu Admin can update the system variables.
 * Kasu epoch number always starts from 0.
 */
contract SystemVariables is ISystemVariables, KasuAccessControllable, Initializable {
    /// @notice Maximum number of loyalty levels in addition to the default level.
    uint256 public constant MAX_ADDITIONAL_LOYALTY_LEVELS = 10;

    /// @notice The duration of one epoch.
    uint256 private constant EPOCH_DURATION = 1 weeks;

    /// @notice The KSU token price contract.
    IKsuPrice private immutable _ksuPrice;

    /// @notice The timestamp of the start of the initial epoch.
    uint256 private _initialEpochStartTimestamp;

    /// @notice The length of the clearing period.
    uint256 public clearingPeriodLength;

    /// @notice The epoch number when the price was last updated.
    uint256 public priceUpdateEpoch;

    /// @notice The price of the KSU token for the epoch.
    /// @dev The price is locked for the duration of the epoch. Updated when updateKsuEpochTokenPrice is called.
    uint256 public ksuEpochTokenPrice;

    /// @notice The performance fee percentage.
    uint256 public performanceFee;

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

    /// @notice Mapping to the tranche name index based on tranche count and tranche index.
    mapping(uint256 trancheCount => mapping(uint256 trancheIndex => uint256 trancheNameIndex)) private
        _trancheNameIndexes;

    /// @notice Returns the default names and symbols for tranche.
    mapping(uint256 trancheNameIndex => TrancheInfo trancheInfo) private _trancheNameInfo;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param ksuPrice_ The KSU token price contract.
     * @param controller_ The Kasu controller contract.
     */
    constructor(IKsuPrice ksuPrice_, IKasuController controller_) KasuAccessControllable(controller_) {
        AddressLib.checkIfZero(address(ksuPrice_));
        AddressLib.checkIfZero(address(controller_));

        _ksuPrice = ksuPrice_;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract.
     * @param systemVariablesSetup The system variables setup structure.
     */
    function initialize(SystemVariablesSetup calldata systemVariablesSetup) external initializer {
        if (
            systemVariablesSetup.initialEpochStartTimestamp > block.timestamp
                || systemVariablesSetup.initialEpochStartTimestamp + EPOCH_DURATION <= block.timestamp
        ) {
            revert InvalidConfiguration();
        }

        if (
            systemVariablesSetup.clearingPeriodLength == 0
                || systemVariablesSetup.clearingPeriodLength >= EPOCH_DURATION
        ) {
            revert InvalidConfiguration();
        }

        _initialEpochStartTimestamp = systemVariablesSetup.initialEpochStartTimestamp;
        clearingPeriodLength = systemVariablesSetup.clearingPeriodLength;

        _setPerformanceFee(systemVariablesSetup.performanceFee);
        _setFeeRates(systemVariablesSetup.ecosystemFeeRate, systemVariablesSetup.protocolFeeRate);
        _setProtocolFeeReceiver(systemVariablesSetup.protocolFeeReceiver);

        _setLoyaltyThresholds(systemVariablesSetup.loyaltyThresholds);

        _updateKsuTokenPrice();

        _defaultTrancheInterestChangeEpochDelay = 4;
        _maxTrancheInterestRate = INTEREST_RATE_FULL_PERCENT / 20; // 5%
        _minTrancheCountPerLendingPool = 1;
        _maxTrancheCountPerLendingPool = 3;

        _trancheNameInfo[0] = TrancheInfo("Junior Tranche", "jr");
        _trancheNameInfo[1] = TrancheInfo("Mezzanine Tranche", "mz");
        _trancheNameInfo[2] = TrancheInfo("Senior Tranche", "sr");

        _trancheNameIndexes[1][0] = 2;
        _trancheNameIndexes[2][0] = 0;
        _trancheNameIndexes[2][1] = 2;
        _trancheNameIndexes[3][0] = 0;
        _trancheNameIndexes[3][1] = 1;
        _trancheNameIndexes[3][2] = 2;
    }

    /* ========== EPOCH ========== */

    /**
     * @notice Returns the current epoch number.
     * @return The current epoch number.
     */
    function currentEpochNumber() public view returns (uint256) {
        if (block.timestamp < _initialEpochStartTimestamp) {
            return 0;
        }

        return (block.timestamp - _initialEpochStartTimestamp) / EPOCH_DURATION;
    }

    /**
     * @notice Returns the timestamp of the start of the given epoch.
     * @param epoch The epoch number.
     * @return The timestamp of the start of the given epoch.
     */
    function epochStartTimestamp(uint256 epoch) external view returns (uint256) {
        return _initialEpochStartTimestamp + epoch * EPOCH_DURATION;
    }

    /**
     * @notice Returns the duration of an epoch.
     * @return The duration of an epoch.
     */
    function epochDuration() external pure returns (uint256) {
        return EPOCH_DURATION;
    }

    /**
     * @notice Returns the timestamp of the start of the next epoch.
     * @return The timestamp of the start of the next epoch.
     */
    function nextEpochStartTimestamp() public view returns (uint256) {
        return _initialEpochStartTimestamp + (currentEpochNumber() + 1) * EPOCH_DURATION;
    }

    /**
     * @notice Returns the current epoch request number.
     * @dev If the current epoch is in the clearing period, the next epoch number is returned.
     * @return requestEpoch The current epoch request number.
     */
    function currentRequestEpoch() external view returns (uint256 requestEpoch) {
        requestEpoch = currentEpochNumber();

        if (isClearingTime()) {
            requestEpoch++;
        }
    }

    /* ========== CLEARING PERIOD ========== */

    /**
     * @notice Checks if the current epoch is in the clearing period.
     * @return True if the current epoch is in the clearing period, false otherwise.
     */
    function isClearingTime() public view returns (bool) {
        return nextEpochStartTimestamp() - block.timestamp <= clearingPeriodLength;
    }

    /* ========== TOKEN PRICE ========== */

    /**
     * @notice Updates the price of the KSU token at the start of the epoch.
     * @dev This function should be called at the start of each epoch by anyone.
     */
    function updateKsuEpochTokenPrice() external {
        if (currentEpochNumber() > priceUpdateEpoch) {
            _updateKsuTokenPrice();
        }
    }

    /**
     * @notice Returns the KSU epoch token price, falling back to the spot price when the stored snapshot is stale.
     * @dev Defense-in-depth for view callers (loyalty reads) when neither the cron nor clearing has refreshed the
     * snapshot for the current epoch yet.
     */
    function ksuEpochTokenPriceFresh() external view returns (uint256) {
        if (currentEpochNumber() > priceUpdateEpoch) {
            return _ksuPrice.ksuTokenPrice();
        }
        return ksuEpochTokenPrice;
    }

    function _updateKsuTokenPrice() internal {
        priceUpdateEpoch = currentEpochNumber();
        ksuEpochTokenPrice = _ksuPrice.ksuTokenPrice();

        emit KsuTokenPriceUpdated(priceUpdateEpoch, ksuEpochTokenPrice);
    }

    /* ========== PERFORMANCE FEE ========== */

    /**
     * @notice Sets the performance fee.
     * @dev The performance fee is denominated in FULL_PERCENT and cannot exceed it.
     * @param performanceFee_ The new performance fee.
     */
    function setPerformanceFee(uint256 performanceFee_) external onlyAdmin {
        _setPerformanceFee(performanceFee_);
    }

    function _setPerformanceFee(uint256 performanceFee_) internal {
        if (performanceFee_ > FULL_PERCENT) {
            revert InvalidConfiguration();
        }

        performanceFee = performanceFee_;

        emit PerformanceFeeUpdated(performanceFee_);
    }

    /* ========== LOYALTY THRESHOLDS ========== */

    /**
     * @notice Returns the loyalty thresholds.
     * @dev The loyalty thresholds are denominated in FULL_PERCENT.
     * Index 0 represents loyalty level 1, and the last index is the highest loyalty level.
     * Loyalty level 0 is assumed by default, is not part of this array, and it should have 0% threshold.
     * @return The loyalty thresholds.
     */
    function loyaltyThresholds() external view returns (uint256[] memory) {
        return _loyaltyThresholds;
    }

    /**
     * @notice Returns the number of loyalty levels including the default level.
     * @return The number of loyalty levels is the number of thresholds plus 1.
     */
    function loyaltyLevelsCount() external view returns (uint8) {
        return uint8(_loyaltyThresholds.length + 1);
    }

    /**
     * @notice Sets the loyalty thresholds percentages.
     * @dev The loyalty thresholds are denominated in FULL_PERCENT and values must be in ascending order.
     * Index 0 represents loyalty level 1, and the last index is the highest loyalty level.
     * If array has no elements then there is only one loyalty level.
     * @param loyaltyThresholds_ The new loyalty thresholds array.
     */
    function setLoyaltyThresholds(uint256[] calldata loyaltyThresholds_) external onlyAdmin {
        if (isClearingTime()) {
            revert CannotConfigureDuringClearingPeriod();
        }

        _setLoyaltyThresholds(loyaltyThresholds_);
    }

    function _setLoyaltyThresholds(uint256[] calldata loyaltyThresholds_) internal {
        if (loyaltyThresholds_.length > MAX_ADDITIONAL_LOYALTY_LEVELS) {
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

        emit LoyaltyThresholdsUpdated(loyaltyThresholds_);
    }

    /* ========== LENDING POOL ========== */

    /**
     * @notice Returns whether users can only deposit to junior tranches only when having rKSU.
     * @return true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around.
     */
    function userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool) {
        return _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU;
    }

    /**
     * @notice Sets whether users are allowed to deposit to junior tranche only when the own rKSU.
     * @param value Set to true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around.
     */
    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external onlyAdmin {
        _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU = value;

        emit UserCanOnlyDepositToJuniorTrancheWhenHeHasRKSUUpdated(value);
    }

    /* ========== TRANCHE ========== */

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
        onlyAdmin
    {
        _defaultTrancheInterestChangeEpochDelay = defaultTrancheInterestChangeEpochDelay_;

        emit DefaultTrancheInterestChangeEpochDelayUpdated(defaultTrancheInterestChangeEpochDelay_);
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
    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) public onlyAdmin {
        _maxTrancheInterestRate = maxTrancheInterestRate_;

        emit MaxTrancheInterestRateUpdated(maxTrancheInterestRate_);
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
     * @notice Return the default tranche name and symbol based on tranche count and tranche index.
     * @param trancheCount The tranche count.
     * @param trancheIndex The tranche index.
     * @return The default tranche name and symbol.
     */
    function trancheNameInfo(uint256 trancheCount, uint256 trancheIndex) external view returns (TrancheInfo memory) {
        if (
            trancheCount < _minTrancheCountPerLendingPool || trancheCount > _maxTrancheCountPerLendingPool
                || trancheIndex >= trancheCount
        ) {
            revert InvalidConfiguration();
        }

        return _trancheNameInfo[_trancheNameIndexes[trancheCount][trancheIndex]];
    }

    /* ========== FEES ========== */

    /**
     * @notice Returns the protocol fee rate.
     * @return ecosystemFeeRate The ecosystem fee rate.
     * @return protocolFeeRate The protocol fee rate.
     */
    function feeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate) {
        return (_ecosystemFeeRate, _protocolFeeRate);
    }

    /**
     * @notice Sets the split ratio for the collected fees.
     * @dev The sum of the ecosystem and protocol fee rates must be equal to FULL_PERCENT.
     * @param ecosystemFeeRate The ecosystem fee rate.
     * @param protocolFeeRate The protocol fee rate.
     */
    function setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) external onlyAdmin {
        _setFeeRates(ecosystemFeeRate, protocolFeeRate);
    }

    function _setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) private {
        if (ecosystemFeeRate + protocolFeeRate != FULL_PERCENT) {
            revert InvalidConfiguration();
        }
        _ecosystemFeeRate = ecosystemFeeRate;
        _protocolFeeRate = protocolFeeRate;

        emit FeeRatesUpdated(ecosystemFeeRate, protocolFeeRate);
    }

    /**
     * @notice Returns the protocol fee receiver.
     * @return The protocol fee receiver.
     */
    function protocolFeeReceiver() public view returns (address) {
        return _protocolFeeReceiver;
    }

    /**
     * @notice Sets the protocol fee receiver.
     * @param receiver The protocol fee receiver.
     */
    function setProtocolFeeReceiver(address receiver) public onlyAdmin {
        _setProtocolFeeReceiver(receiver);
    }

    function _setProtocolFeeReceiver(address receiver) private {
        AddressLib.checkIfZero(receiver);
        _protocolFeeReceiver = receiver;

        emit ProtocolFeeReceiverUpdated(receiver);
    }
}
