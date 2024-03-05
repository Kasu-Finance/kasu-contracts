// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../shared/access/KasuAccessControllable.sol";
import "./interfaces/IKasuAllowList.sol";
import "../shared/access/KasuController.sol";

contract KasuAllowList is IKasuAllowList, KasuAccessControllable {
    constructor(KasuController kasuController_) KasuAccessControllable(kasuController_) {}

    /// @notice Manual allow list of users.
    mapping(address => bool) public allowList;

    /// @notice Block list of users.
    /// @dev If a user is in the block list, it will be blocked even if it is in the allow list or KYCd.
    mapping(address => bool) public blockList;

    function allowUser(address user) external onlyAdmin {
        if (!allowList[user]) {
            allowList[user] = true;
            emit IKasuAllowList.UserAddedInAllowList(user);
        }
    }

    function disallowUser(address user) external onlyAdmin {
        if (allowList[user]) {
            allowList[user] = false;
            emit IKasuAllowList.UserRemovedFromAllowList(user);
        }
    }

    function blockUser(address user) external onlyAdmin {
        if (!blockList[user]) {
            blockList[user] = true;
            emit IKasuAllowList.UserBlockedFromAllowList(user);
        }
    }

    function unblockUser(address user) external onlyAdmin {
        if (blockList[user]) {
            blockList[user] = false;
            emit IKasuAllowList.UserUnblockedFromAllowList(user);
        }
    }

    function isAllowed(address user) external view returns (bool) {
        return !blockList[user] && allowList[user];
    }
}
