// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Tranche name and token symbol.
 * @custom:member trancheName Tranche name.
 * @custom:member tokenSymbol Token symbol.   
 */
struct TrancheInfo {
    string trancheName;
    string tokenSymbol;
}

interface ISystemVariables {
    /* ========== EPOCH ========== */

    function currentEpochNumber() external view returns (uint256);
    function currentRequestEpoch() external view returns (uint256 requestEpoch);
    function epochStartTimestamp(uint256 epoch) external view returns (uint256);
    function epochDuration() external view returns (uint256);
    function nextEpochStartTimestamp() external view returns (uint256);

    /* ========== CLEARING PERIOD ========== */

    function isClearingTime() external view returns (bool);
    function clearingPeriodLength() external view returns (uint256);

    /* ========== TOKEN PRICE ========== */

    function ksuEpochTokenPrice() external view returns (uint256);
    function priceUpdateEpoch() external view returns (uint256);
    function updateKsuEpochTokenPrice() external;

    /* ========== LOYALTY THRESHOLD ========== */

    function loyaltyThresholds() external view returns (uint256[] memory loyaltyThresholds);
    function loyaltyLevelsCount() external view returns (uint8);
    function setLoyaltyThresholds(uint256[] calldata loyaltyThresholds) external;

    /* ========== LENDING POOL ========== */

    function userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool);
    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external;

    /* ========== TRANCHE ========== */ 

    function defaultTrancheInterestChangeEpochDelay() external view returns (uint256);
    function setDefaultTrancheInterestChangeEpochDelay(uint256 defaultTrancheInterestChangeEpochDelay_) external;

    function maxTrancheInterestRate() external view returns (uint256);
    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) external;

    function minTrancheCountPerLendingPool() external view returns (uint256);
    function maxTrancheCountPerLendingPool() external view returns (uint256);

    function trancheNameInfo(uint256 trancheCount, uint256 trancheIndex) external view returns (TrancheInfo memory);

    /* ========== PERFORMANCE FEE ========== */

    function setPerformanceFee(uint256 performanceFee) external;
    function performanceFee() external view returns (uint256);

    function feeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate);
    function setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) external;

    function protocolFeeReceiver() external view returns (address);
    function setProtocolFeeReceiver(address receiver) external;

    /* ========== EVENTS ========== */

    event PerformanceFeeUpdated(uint256 performanceFee);
    event KsuTokenPriceUpdated(uint256 indexed epoch, uint256 ksuTokenPrice);
    event LoyaltyThresholdsUpdated(uint256[] loyaltyThresholds);
    event UserCanOnlyDepositToJuniorTrancheWhenHeHasRKSUUpdated(bool value);
    event DefaultTrancheInterestChangeEpochDelayUpdated(uint256 defaultTrancheInterestChangeEpochDelay);
    event MaxTrancheInterestRateUpdated(uint256 maxTrancheInterestRate);
    event FeeRatesUpdated(uint256 ecosystemFeeRate, uint256 protocolFeeRate);
    event ProtocolFeeReceiverUpdated(address receiver);

    /* ========== ERRORS ========== */

    error CannotConfigureDuringClearingPeriod();
}
