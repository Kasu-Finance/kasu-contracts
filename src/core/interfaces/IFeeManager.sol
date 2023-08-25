// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

struct PlatformFeeConfiguration {
    //
}

interface IFeeManager {
    function receiveYieldFee() external;

    configurePlatformFee(PlatformFeeConfiguration configuration) external;
}
