// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKasuAllowList {
    function allowUser(address user) external;
    function disallowUser(address user) external;
    function blockUser(address user) external;
    function unblockUser(address user) external;
    function isAllowed(address user) external view returns (bool);

    event UserAddedInAllowList(address user);
    event UserRemovedFromAllowList(address user);
    event UserBlockedFromAllowList(address user);
    event UserUnblockedFromAllowList(address user);

    error UserNotInAllowList(address user);
}
