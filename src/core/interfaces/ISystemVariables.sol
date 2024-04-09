// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct TrancheInfo {
    string trancheName;
    string tokenSymbol;
}

interface ISystemVariables {
    // EPOCH
    function currentEpochNumber() external view returns (uint256);
    function currentRequestEpoch() external view returns (uint256 requestEpoch);
    function epochStartTimestamp(uint256 epoch) external view returns (uint256);
    function epochDuration() external view returns (uint256);
    function nextEpochStartTimestamp() external view returns (uint256);

    // CLEARING PERIOD
    function isClearingTime() external view returns (bool);
    function clearingPeriodLength() external view returns (uint256);

    // TOKEN PRICE
    function ksuEpochTokenPrice() external view returns (uint256);
    function priceUpdateEpoch() external view returns (uint256);
    function updateKsuEpochTokenPrice() external;

    // FEES
    function setPerformanceFee(uint256 performanceFee) external;
    function performanceFee() external view returns (uint256);

    // LOYALTY THRESHOLD
    function loyaltyThresholds() external view returns (uint256[] memory loyaltyThresholds);
    function loyaltyLevelsCount() external view returns (uint8);
    function setLoyaltyThresholds(uint256[] calldata loyaltyThresholds) external;

    // LENDING POOL
    function getUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool);
    function setUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU(bool value) external;

    // TRANCHE
    function defaultTrancheInterestChangeEpochDelay() external view returns (uint256);
    function setDefaultTrancheInterestChangeEpochDelay(uint256 defaultTrancheInterestChangeEpochDelay_) external;

    function maxTrancheInterestRate() external view returns (uint256);
    function setMaxTrancheInterestRate(uint256 maxTrancheInterestRate_) external;

    function minTrancheCountPerLendingPool() external view returns (uint256);
    function maxTrancheCountPerLendingPool() external view returns (uint256);

    function getTrancheInfo(uint256 index) external view returns (TrancheInfo memory);

    // FEES
    function getFeeRates() external view returns (uint256 ecosystemFeeRate, uint256 protocolFeeRate);
    function setFeeRates(uint256 ecosystemFeeRate, uint256 protocolFeeRate) external;

    function getProtocolFeeReceiver() external view returns (address);
    function setProtocolFeeReceiver(address receiver) external;

    // EVENTS
    event PerformanceFeeUpdated(uint256 performanceFee);
    event KsuTokenPriceUpdated(uint256 indexed epoch, uint256 ksuTokenPrice);

    // ERRORS
    error CannotConfigureDuringClearingPeriod();
}
