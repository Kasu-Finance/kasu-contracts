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

    struct ERC20Permit {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId);
    function lockWithPermit(uint256 amount, uint256 lockPeriod, ERC20Permit calldata ksuPermit)
        external
        returns (uint256 userLockId);
    function unlock(uint256 amount, uint256 userLockId) external;
    function emitFees(uint256 amount) external;
    function claimFees() external returns (uint256 earned);
    function getRewards(address user) external view returns (uint256);
}
