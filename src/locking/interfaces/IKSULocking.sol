// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {rKSU} from "../rKSU.sol";

// Errors
error LockPeriodNotSupported(uint256 lockPeriod);
error DepositLocked(uint256 lockPeriod);
error InvalidUserDeposit(uint256 userLockId);
error UserUnlockAmountTooHigh(uint256 userLockId, uint256 lockAmount, uint256 requestedUnlockAmount);

// Events
event UserLocked(address indexed user, uint256 indexed lockId, uint256 amount, uint256 ksuBonusAmount);

event UserUnlocked(address indexed user, uint256 indexed lockId, uint256 amount);

event FeesClaimed(address indexed user, uint256 amount);

event FeesEmitted(address indexed user, uint256 amount);

event LockPeriodAdded(uint256 indexed lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier);

interface IKSULocking {
    struct UserLock {
        uint256 amount;
        uint256 rKSUAmount;
        uint256 rKSUMultiplier;
        uint256 startTime;
        uint256 lockPeriod;
    }

    struct ERC20PermitPayload {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Add period lock details
     * @param lockPeriod in seconds
     * @param rKSUMultiplier xKSU multiplier for the lock period
     */
    function addLockPeriod(uint256 lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier) external;

    /**
     * @notice Lock KSU token for a period of time
     * @dev User must approve KSU token before calling this function
     * @param amount KSU token amount to lock
     * @param lockPeriod in seconds
     * @return userLockId lock id
     */
    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId);

    /**
     * @notice Lock KSU token for a period of time
     * @param amount KSU token amount to lock
     * @param lockPeriod in seconds
     * @param ksuPermit KSU token permit
     * @return userLockId lock id
     */
    function lockWithPermit(uint256 amount, uint256 lockPeriod, ERC20PermitPayload calldata ksuPermit)
        external
        returns (uint256 userLockId);

    /**
     * @notice Unlock KSU token. Locking period must over.
     * @param amount KSU token amount to unlock
     * @param userLockId lock id
     */
    function unlock(uint256 amount, uint256 userLockId) external;

    /**
     * @notice Adding USDC to the locking contracts
     * @dev Must approve USDC token before calling this function
     * @param amount amount of fees to add
     */
    function emitFees(uint256 amount) external;

    /**
     * @notice Called by user to get all his USDC fees
     */
    function claimFees() external returns (uint256 earned);

    /**
     * @notice Returns USDC user reward amount
     */
    function getRewards(address user) external view returns (uint256);

    /**
     * @notice Sets the KSU Bonus Tokens contract address
     */
    function setKSULockBonus(address ksuBonusTokens_) external;
}
