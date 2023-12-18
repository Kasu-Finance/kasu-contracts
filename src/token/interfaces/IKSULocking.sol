// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

error LockPeriodNotSupported(uint256 lockPeriod);
error DepositLocked(uint256 lockPeriod);
error InvalidUserDeposit(uint256 userLockId);
error UserUnlockAmountTooHigh(uint256 userLockId, uint256 lockAmount, uint256 requestedUnlockAmount);

interface IKSULocking {
    struct UserLock {
        uint256 amount;
        uint256 rKSUAmount;
        uint256 rKSUMultiplier;
        uint256 startTime;
        uint256 lockPeriod;
    }

    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId);
    function unlock(uint256 amount, uint256 userLockId) external;

    function emitFees(uint256 amount) external;
    function claimFees() external returns (uint256 earned);
}
