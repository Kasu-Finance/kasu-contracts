// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKasuAllowList {
    function allowUser(address user) external;

    function blockUser(address user) external;

    function isAllowed(address user) external returns (bool);

    error UserNotInAllowList(address user);
}
