// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IKSULocking {
    struct UserLock {
        uint256 amount;
        uint256 xKSUAmount;
        uint256 startTime;
        uint256 lockPeriod;
    }

    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId);
    function unlock(uint256 amount, uint256 userLockId) external;

    function emitFees(uint256 amount) external;
    function claimFees() external returns (uint256 earned);
}
