// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface ISystemVariables {
    function ksuTokenPrice() external view returns (uint256);
    function updateKsuTokenPrice() external;

    function getCurrentEpochNumber() external view returns (uint256);
    function getCurrentRequestEpoch() external view returns (uint256 requestEpoch);
    function getEpochStartTimestamp(uint256 epoch) external view returns (uint256);
    function getEpochDuration() external view returns (uint256);
    function getNextEpochStartTimestamp() external view returns (uint256);
    function isClearingTime() external view returns (bool);
    function clearingPeriodLength() external view returns (uint256);

    function setProtocolFee(uint256 protocolFee) external;
    function protocolFee() external view returns (uint256);

    // EVENTS
    event ProtocolFeeUpdated(uint256 protocolFee);
    event KsuTokenPriceUpdated(uint256 indexed epoch, uint256 ksuTokenPrice);

    // ERRORS
    error InvalidEpochNumber();
}
