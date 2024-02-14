// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface ISystemVariables {
    // EPOCH
    function getCurrentEpochNumber() external view returns (uint256);
    function getCurrentRequestEpoch() external view returns (uint256 requestEpoch);
    function getEpochStartTimestamp(uint256 epoch) external view returns (uint256);
    function getEpochDuration() external view returns (uint256);
    function getNextEpochStartTimestamp() external view returns (uint256);

    // CLEARING PERIOD
    function isClearingTime() external view returns (bool);
    function clearingPeriodLength() external view returns (uint256);

    // TOKEN PRICE
    function ksuEpochTokenPrice() external view returns (uint256);
    function getPriceUpdateEpoch() external view returns (uint256);
    function updateKsuEpochTokenPrice() external;

    // PROTOCOL FEE
    function setProtocolFee(uint256 protocolFee) external;
    function protocolFee() external view returns (uint256);

    // LOYALTY THRESHOLD
    function loyaltyThresholds() external view returns (uint256[] memory loyaltyThresholds);
    function setLoyaltyThresholds(uint256[] calldata loyaltyThresholds) external;

    // LENDING POOL
    function getUserCanDepositToJuniorTrancheWhenHeHasRKSU() external view returns (bool);
    function setUserCanDepositToJuniorTrancheWhenHeHasRKSU(bool value) external;

    // EVENTS
    event ProtocolFeeUpdated(uint256 protocolFee);
    event KsuTokenPriceUpdated(uint256 indexed epoch, uint256 ksuTokenPrice);

    // ERRORS
    error CannotConfigureDuringClearingPeriod();
}
