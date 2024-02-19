// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../shared/access/KasuAccessControllable.sol";
import "./interfaces/IKasuAllowList.sol";
import "../shared/access/KasuController.sol";

contract KasuAllowList is IKasuAllowList, KasuAccessControllable {
    constructor(KasuController kasuController_) KasuAccessControllable(kasuController_) {}

    mapping(address => bool) private _allowList;

    function allowUser(address user) external onlyAdmin {
        _allowList[user] = true;
    }

    function blockUser(address user) external onlyAdmin {
        _allowList[user] = false;
    }

    function isAllowed(address user) external view returns (bool) {
        return _allowList[user];
    }
}
