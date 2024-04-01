// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IFeeManager.sol";
import "../locking/interfaces/IKSULocking.sol";
import "./AssetFunctionsBase.sol";
import "./interfaces/ISystemVariables.sol";
import "./Constants.sol";
import "../shared/access/KasuAccessControllable.sol";

contract FeeManager is IFeeManager, AssetFunctionsBase, KasuAccessControllable {
    IKSULocking private immutable _ksuLocking;
    ISystemVariables private immutable _systemVariables;

    uint256 public totalProtocolFeeAmount;

    constructor(
        address underlyingAsset_,
        ISystemVariables systemVariables_,
        IKasuController controller_,
        IKSULocking ksuLocking_
    ) AssetFunctionsBase(underlyingAsset_) KasuAccessControllable(controller_) {
        _ksuLocking = ksuLocking_;
        _systemVariables = systemVariables_;
    }

    function emitFees(uint256 amount) external whenNotPaused {
        _transferAssetsFrom(msg.sender, address(this), amount);

        (uint256 ecosystemFeeRate,) = _systemVariables.getFeeRates();

        uint256 ecosystemFeeAmount = ecosystemFeeRate * amount / FULL_PERCENT;
        _approveAsset(address(_ksuLocking), ecosystemFeeAmount);
        _ksuLocking.emitFees(ecosystemFeeAmount);

        uint256 protocolFeeAmount = amount - ecosystemFeeAmount;
        totalProtocolFeeAmount += protocolFeeAmount;

        emit FeesEmitted(msg.sender, ecosystemFeeAmount, protocolFeeAmount);
    }

    function claimProtocolFees() external whenNotPaused onlyRole(ROLE_PROTOCOL_FEE_CLAIMER, msg.sender) {
        address protocolFeeReceiver = _systemVariables.getProtocolFeeReceiver();
        if (protocolFeeReceiver == address(0)) {
            revert ConfigurationAddressZero();
        }
        uint256 totalProtocolFeeAmount_ = totalProtocolFeeAmount;
        totalProtocolFeeAmount = 0;
        _transferAssets(protocolFeeReceiver, totalProtocolFeeAmount_);

        emit ProtocolFeesClaimed(protocolFeeReceiver, totalProtocolFeeAmount_);
    }
}
