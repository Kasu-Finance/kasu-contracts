// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";
import {SystemVariablesSetup} from "./SystemVariables.sol";

/**
 * @notice TEMPORARY migration implementation of SystemVariables used to bootstrap
 *         a new deployment with an aligned epoch number to pre-existing chains.
 *
 * @dev This is IDENTICAL to SystemVariables EXCEPT the `initialize` function
 *      omits the past-timestamp validation check, allowing the initial epoch
 *      start to be set to a timestamp more than EPOCH_DURATION in the past.
 *
 *      This is required because SystemVariables.initialize rejects timestamps
 *      outside `[now - 1 week, now]`, preventing a fresh deployment from being
 *      aligned to an older anchor (e.g. to match XDC AUDD's epoch numbering).
 *
 *      Storage layout MUST remain byte-identical to SystemVariables so that
 *      upgrading the proxy to this impl, initializing, then upgrading back to
 *      the production SystemVariables impl works cleanly.
 *
 *      USAGE:
 *      1. Upgrade SystemVariables proxy to this impl with an upgradeAndCall
 *         that invokes initialize(setup) with the desired aligned timestamp.
 *      2. Immediately upgrade the proxy back to the production SystemVariables impl.
 *
 *      DO NOT leave this impl in place on a production deployment.
 */
contract SystemVariablesMigration is ISystemVariables, KasuAccessControllable, Initializable {
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
    uint256 private _maxTrancheInterestRate;

    /// @notice The minimum tranche count per lending pool.
    uint256 private _minTrancheCountPerLendingPool;

    /// @notice The maximum tranche count per lending pool.
    uint256 private _maxTrancheCountPerLendingPool;

    /// @notice The ecosystem fee percentage rate.
    uint256 private _ecosystemFeeRate;

    /// @notice The protocol fee percentage rate.
    uint256 private _protocolFeeRate;

    /// @notice The protocol fee receiver.
    address private _protocolFeeReceiver;

    /// @notice Mapping to the tranche name index based on tranche count and tranche index.
    mapping(uint256 trancheCount => mapping(uint256 trancheIndex => uint256 trancheNameIndex)) private
        _trancheNameIndexes;

    /// @notice Returns the default names and symbols for tranche.
    mapping(uint256 trancheNameIndex => TrancheInfo trancheInfo) private _trancheNameInfo;

    /* ========== CONSTRUCTOR ========== */

    constructor(IKsuPrice ksuPrice_, IKasuController controller_) KasuAccessControllable(controller_) {
        AddressLib.checkIfZero(address(ksuPrice_));
        AddressLib.checkIfZero(address(controller_));

        _ksuPrice = ksuPrice_;
        _disableInitializers();
    }

    /* ========== INITIALIZER (past-timestamp check REMOVED) ========== */

    function initialize(SystemVariablesSetup calldata systemVariablesSetup) external initializer {
        // NOTE: The past-timestamp validation from SystemVariables.initialize is intentionally
        // omitted here. This is the sole purpose of this migration impl.
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

    function currentEpochNumber() public view returns (uint256) {
        if (block.timestamp < _initialEpochStartTimestamp) {
            return 0;
        }
        return (block.timestamp - _initialEpochStartTimestamp) / EPOCH_DURATION;
    }

    function epochStartTimestamp(uint256 epoch) external view returns (uint256) {
        return _initialEpochStartTimestamp + epoch * EPOCH_DURATION;
    }

    function epochDuration() external pure returns (uint256) {
        return EPOCH_DURATION;
    }

    function nextEpochStartTimestamp() public view returns (uint256) {
        return _initialEpochStartTimestamp + (currentEpochNumber() + 1) * EPOCH_DURATION;
    }

    function currentRequestEpoch() external view returns (uint256 requestEpoch) {
        requestEpoch = currentEpochNumber();
        if (isClearingTime()) {
            requestEpoch++;
        }
    }

    /* ========== CLEARING PERIOD ========== */

    function isClearingTime() public view returns (bool) {
        return nextEpochStartTimestamp() - block.timestamp <= clearingPeriodLength;
    }

    /* ========== TOKEN PRICE ========== */

    function updateKsuEpochTokenPrice() external {
        if (currentEpochNumber() > priceUpdateEpoch) {
            _updateKsuTokenPrice();
        }
    }

    function _updateKsuTokenPrice() internal {
        priceUpdateEpoch = currentEpochNumber();
        ksuEpochTokenPrice = _ksuPrice.ksuTokenPrice();
        emit KsuTokenPriceUpdated(priceUpdateEpoch, ksuEpochTokenPrice);
    }

    /* ========== PERFORMANCE FEE ========== */

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

    function loyaltyThresholds() external view returns (uint256[] memory) {
        return _loyaltyThresholds;
    }

    function loyaltyLevelsCount() external view returns (uint8) {
        return uint8(_loyaltyThresholds.length + 1);
    }

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

    function userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool) {
        return _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU;
    }

    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external onlyAdmin {
        _userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU = value;
        emit UserCanOnlyDepositToJuniorTrancheWhenHeHasRKSUUpdated(value);
    }

    /* ========== TRANCHE ========== */

    function defaultTrancheInterestChangeEpochDelay() external view returns (uint256) {
        return _defaultTrancheInterestChangeEpochDelay;
    }

    function setDefaultTrancheInterestChangeEpochDelay(uint256 defaultTrancheInterestChangeEpochDelay_)
        public
        onlyAdmin
    {
        _defaultTrancheInterestChangeEpochDelay = defaultTrancheInterestChangeEpochDelay_;
        emit DefaultTrancheInterestChangeEpochDelayUpdated(defaultTrancheInterestChangeEpochDelay_);
    }

    function maxTrancheInterestRate() external view returns (uint256) {
        return _maxTrancheInterestRate;
    }

    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) public onlyAdmin {
        _maxTrancheInterestRate = maxTrancheInterestRate_;
        emit MaxTrancheInterestRateUpdated(maxTrancheInterestRate_);
    }

    function minTrancheCountPerLendingPool() external view returns (uint256) {
        return _minTrancheCountPerLendingPool;
    }

    function maxTrancheCountPerLendingPool() external view returns (uint256) {
        return _maxTrancheCountPerLendingPool;
    }

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

    function feeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate) {
        return (_ecosystemFeeRate, _protocolFeeRate);
    }

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

    function protocolFeeReceiver() public view returns (address) {
        return _protocolFeeReceiver;
    }

    function setProtocolFeeReceiver(address receiver) public onlyAdmin {
        _setProtocolFeeReceiver(receiver);
    }

    function _setProtocolFeeReceiver(address receiver) private {
        AddressLib.checkIfZero(receiver);
        _protocolFeeReceiver = receiver;
        emit ProtocolFeeReceiverUpdated(receiver);
    }
}
