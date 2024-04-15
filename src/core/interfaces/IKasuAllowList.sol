// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKasuAllowList {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function allowList(address) external view returns (bool);
    function blockList(address) external view returns (bool);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function allowUser(address user) external;
    function disallowUser(address user) external;
    function blockUser(address user) external;
    function unblockUser(address user) external;
    function verifyUserKyc(address user, uint256 blockExpiration, bytes calldata signature) external returns (bool);

    /* ========== EVENTS ========== */

    event UserAddedInAllowList(address user);
    event UserRemovedFromAllowList(address user);
    event UserBlockedFromAllowList(address user);
    event UserUnblockedFromAllowList(address user);

    /* ========== ERRORS ========== */

    error UserBlocked(address user);
    error UserNotInAllowList(address user);
    error UserNotKycd(address user);
}
