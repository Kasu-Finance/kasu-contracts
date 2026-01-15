// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IKSULocking.sol";

/**
 * @title KSULockingLite
 * @notice Lite implementation that disables KSU locking behavior.
 */
contract KSULockingLite is IKSULocking {
    mapping(address => uint256) public override userTotalDeposits;

    // ERC20 interface: always return 0 or false.
    function name() public pure returns (string memory) {
        return "KSULockingLite";
    }

    function symbol() public pure returns (string memory) {
        return "KSU_LITE";
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public pure override returns (uint256) {
        return 0;
    }

    function balanceOf(address) public pure override returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function allowance(address, address) public pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) public pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }

    // IKSULocking pure stubs.
    function canAddressEmitFees(address) external pure override returns (bool) {
        return false;
    }

    function canSetFeeRecipient(address) external pure override returns (bool) {
        return false;
    }

    function isFeeRecipientEnabled(address) external pure override returns (bool) {
        return false;
    }

    function eligibleRKSUForFees() external pure override returns (uint256) {
        return 0;
    }

    function rewards(address) external pure override returns (uint256) {
        return 0;
    }

    function lockDetails(uint256) external pure override returns (LockPeriodDetails memory) {
        return LockPeriodDetails(0, 0, false);
    }

    function userLock(address, uint256) external pure override returns (UserLock memory) {
        return UserLock(0, 0, 0, 0, 0);
    }

    function setKSULockBonus(address) external pure override {}
    function setCanEmitFees(address, bool) external pure override {}
    function setCanSetFeeRecipient(address, bool) external pure override {}
    function addLockPeriod(uint256, uint256, uint256) external pure override {}

    function lock(uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function lockWithPermit(uint256, uint256, ERC20PermitPayload calldata) external pure override returns (uint256) {
        return 0;
    }

    function unlock(uint256, uint256) external pure override {}

    function claimFees() external pure override returns (uint256) {
        return 0;
    }

    function emergencyWithdraw(EmergencyWithdrawInput[] calldata, address) external pure override {}
    function emitFees(uint256) external pure override {}
    function enableFeesForUser(address) external pure override {}
    function disableFeesForUser(address) external pure override {}
}
