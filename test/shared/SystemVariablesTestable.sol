// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../src/core/interfaces/ISystemVariables.sol";
import "../../src/core/interfaces/IKsuPrice.sol";
import "../../src/shared/access/KasuAccessControllable.sol";
import "../../src/shared/CommonErrors.sol";
import "../../src/core/Constants.sol";
import "../../src/core/interfaces/ISystemVariables.sol";

/**
 * @notice Kasu system variables contract setup structure.
 * @custom:member firstEpochStartTimestamp The timestamp of the start of the first epoch. Should be in the past.
 * @custom:member clearingPeriodLength The length of the clearing period.
 * @custom:member performanceFee The performance fee.
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
 * @dev This contract is used to store and manage Kasu system variables.
 * It stores epoch, KSU epoch price and platform fee.
 * Kasu epoch number always starts from 0.
 */
contract SystemVariablesTestable is ISystemVariables, KasuAccessControllable, Initializable {
    IKsuPrice public immutable ksuPrice;

    uint256 private constant _epochDuration = 1 weeks;
    uint256 private _firstEpochStartTimestamp;
    uint256 private _clearingPeriodLength;

    // @notice The epoch number when the price was last updated.
    uint256 public priceUpdateEpoch;
    // @notice The price of the KSU token for the epoch.
    uint256 public ksuEpochTokenPrice;

    uint256 public performanceFee;

    uint256[] private _loyaltyThresholds;

    // @notice Whether users can deposit to junior tranches only when having rKSU.
    bool public userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU;

    // @notice Default epoch delay when tranche interest rate is changed
    uint256 public defaultTrancheInterestChangeEpochDelay;

    // @notice The maximum allowed interest rate allowed in tranche
    uint256 public maxTrancheInterestRate;

    uint256 public minTrancheCountPerLendingPool;
    uint256 public maxTrancheCountPerLendingPool;

    uint256 private _ecosystemFeeRate;
    uint256 private _protocolFeeRate;
    address public protocolFeeReceiver;

    /// @notice Mapping to the tranche name index based on tranche count and tranche index.
    mapping(uint256 trancheCount => mapping(uint256 trancheIndex => uint256 trancheNameIndex)) private
        _trancheNameIndexes;

    /// @notice Returns the default names and symbols for tranche.
    mapping(uint256 trancheNameIndex => TrancheInfo trancheInfo) private _trancheNameInfo;

    // FAKE EPOCH
    uint256 private _epochNumber;
    bool private _isClearingTime;

    constructor(IKsuPrice ksuPrice_, IKasuController controller_) KasuAccessControllable(controller_) {
        ksuPrice = ksuPrice_;
        _disableInitializers();
    }

    function test_mock() external pure {}

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

        defaultTrancheInterestChangeEpochDelay = 4;
        maxTrancheInterestRate = INTEREST_RATE_FULL_PERCENT / 20; // 5%
        minTrancheCountPerLendingPool = 1;
        maxTrancheCountPerLendingPool = 3;

        _trancheNameInfo[0] = TrancheInfo("Junior Tranche", "jr");
        _trancheNameInfo[1] = TrancheInfo("Mezzanine Tranche", "mz");
        _trancheNameInfo[2] = TrancheInfo("Senior Tranche", "sr");

        _trancheNameIndexes[1][0] = 2;
        _trancheNameIndexes[2][0] = 0;
        _trancheNameIndexes[2][1] = 2;
        _trancheNameIndexes[3][0] = 0;
        _trancheNameIndexes[3][1] = 1;
        _trancheNameIndexes[3][2] = 2;

        _ecosystemFeeRate = 50_00;
        _protocolFeeRate = 50_00;

        protocolFeeReceiver = systemVariablesSetup.protocolFeeReceiver;
    }

    function startClearing() external {
        _isClearingTime = true;
    }

    function endClearing() external {
        if (_isClearingTime) {
            _isClearingTime = false;
            _epochNumber++;
        }
    }

    // EPOCH

    /**
     * @notice Returns the current epoch number.
     * @return The current epoch number.
     */
    function currentEpochNumber() public view returns (uint256) {
        return _epochNumber;
    }

    // NOTE: invalid
    /**
     * @notice Returns the timestamp of the start of the given epoch.
     * @param epoch The epoch number.
     * @return The timestamp of the start of the given epoch.
     */
    function epochStartTimestamp(uint256 epoch) external view returns (uint256) {
        return _firstEpochStartTimestamp + epoch * _epochDuration;
    }

    // NOTE: invalid
    /**
     * @notice Returns the duration of an epoch.
     * @return The duration of an epoch.
     */
    function epochDuration() external pure returns (uint256) {
        return _epochDuration;
    }

    /**
     * @notice Returns the timestamp of the start of the next epoch.
     * @return The timestamp of the start of the next epoch.
     */
    function nextEpochStartTimestamp() public view returns (uint256) {
        return _firstEpochStartTimestamp + (currentEpochNumber() + 1) * _epochDuration;
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

    // CLEARING PERIOD

    /**
     * @notice Checks if the current epoch is in the clearing period.
     * @return True if the current epoch is in the clearing period, false otherwise.
     */
    function isClearingTime() public view returns (bool) {
        return _isClearingTime;
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
     * @notice Updates the price of the KSU token at the start of the epoch.
     * @dev This function should be called at the start of each epoch.
     */
    function updateKsuEpochTokenPrice() external {
        if (currentEpochNumber() > priceUpdateEpoch) {
            _updateKsuTokenPrice();
        }
    }

    function _updateKsuTokenPrice() internal {
        priceUpdateEpoch = currentEpochNumber();

        ksuEpochTokenPrice = ksuPrice.getKsuTokenPrice();

        emit KsuTokenPriceUpdated(priceUpdateEpoch, ksuEpochTokenPrice);
    }

    // PERFORMANCE FEE

    /**
     * @dev Sets the performance fee.
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

    // LOYALTY THRESHOLDS

    /**
     * @notice Returns the loyalty thresholds.
     * @return The loyalty thresholds.
     */
    function loyaltyThresholds() external view returns (uint256[] memory) {
        return _loyaltyThresholds;
    }

    function loyaltyLevelsCount() external view returns (uint8) {
        return uint8(_loyaltyThresholds.length + 1);
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
     * @notice Sets whether users are allowed to deposit only when the own rKSU
     * @param value Set to true if they are only allowed to deposit to junior tranche when they have rKSU, false the other way around
     */
    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external onlyAdmin {
        userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU = value;
    }

    // TRANCHE

    /**
     * @notice Sets default epoch delay when tranche interest rate is changed
     * @param defaultTrancheInterestChangeEpochDelay_ The new default epoch delay.
     */
    function setDefaultTrancheInterestChangeEpochDelay(uint256 defaultTrancheInterestChangeEpochDelay_)
        public
        onlyAdmin
    {
        defaultTrancheInterestChangeEpochDelay = defaultTrancheInterestChangeEpochDelay_;
    }

    /**
     * @notice Sets the maximum allowed interest rate per tranche
     * @param maxTrancheInterestRate_ maximum allowed interest rate per tranche
     */
    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) public onlyAdmin {
        maxTrancheInterestRate = maxTrancheInterestRate_;
    }

    /**
     * @notice Return the default tranche name and symbol based on tranche count and tranche index.
     * @param trancheCount The tranche count.
     * @param trancheIndex The tranche index.
     * @return The default tranche name and symbol.
     */
    function trancheNameInfo(uint256 trancheCount, uint256 trancheIndex) external view returns (TrancheInfo memory) {
        if (
            trancheCount < minTrancheCountPerLendingPool || trancheCount > maxTrancheCountPerLendingPool
                || trancheIndex >= trancheCount
        ) {
            revert InvalidConfiguration();
        }

        return _trancheNameInfo[_trancheNameIndexes[trancheCount][trancheIndex]];
    }

    // FEES

    /**
     * @notice Returns the protocol fee rate
     * @return ecosystemFeeRate The ecosystem fee rate
     * @return protocolFeeRate The protocol fee rate
     */
    function feeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate) {
        return (_ecosystemFeeRate, _protocolFeeRate);
    }

    /**
     * @notice Sets the split ratio for the fees.
     * @param ecosystemFeeRate The ecosystem fee rate
     * @param protocolFeeRate The protocol fee rate
     */
    function setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) external {
        if (ecosystemFeeRate + protocolFeeRate != FULL_PERCENT) {
            revert InvalidConfiguration();
        }
        _ecosystemFeeRate = ecosystemFeeRate;
        _protocolFeeRate = protocolFeeRate;
    }

    /**
     * @notice Sets the protocol fee receiver
     * @param receiver The protocol fee receiver
     */
    function setProtocolFeeReceiver(address receiver) public whenNotPaused onlyAdmin {
        if (receiver == address(0)) {
            revert ConfigurationAddressZero();
        }
        protocolFeeReceiver = receiver;
    }
}
