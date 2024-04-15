// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Emergency withdraw input.
 * @custom:member user User address.
 * @custom:member lockId Lock ID.
 * @custom:member withdrawAmount Amount to withdraw.
 */
struct EmergencyWithdrawInput {
    address user;
    uint256 lockId;
    uint256 withdrawAmount;
}

/**
 * @notice User lock details.
 * @custom:member amount Amount of tokens locked.
 * @custom:member rKSUAmount Amount of rKSU minted.
 * @custom:member rKSUMultiplier rKSU multiplier used for the lock.
 * @custom:member startTime Lock start time.
 * @custom:member lockPeriod Lock duration.
 */
struct UserLock {
    uint256 amount;
    uint256 rKSUAmount;
    uint256 rKSUMultiplier;
    uint256 startTime;
    uint256 lockPeriod;
}

/**
 * @notice Lock period details.
 * @custom:member rKSUMultiplier rKSU multiplier for the lock period.
 * @custom:member ksuBonusMultiplier KSU bonus multiplier for the lock period.
 * @custom:member isActive Lock period status.
 */
struct LockPeriodDetails {
    uint256 rKSUMultiplier;
    uint256 ksuBonusMultiplier;
    bool isActive;
}

/**
 * @notice ERC20 permit payload.
 * @custom:member value Amount of tokens.
 * @custom:member deadline Permit deadline.
 * @custom:member v Signature v.
 * @custom:member r Signature r.
 * @custom:member s Signature s.
 */
struct ERC20PermitPayload {
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

interface IKSULocking is IERC20 {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function lockDetails(uint256 lockPeriod) external view returns (LockPeriodDetails memory);

    function userTotalDeposits(address) external view returns (uint256);
    function userLock(address, uint256) external view returns (UserLock memory);
    function rewards(address user) external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function setKSULockBonus(address ksuBonusTokens_) external;
    function addLockPeriod(uint256 lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier) external;

    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId);
    function lockWithPermit(uint256 amount, uint256 lockPeriod, ERC20PermitPayload calldata ksuPermit)
        external
        returns (uint256 userLockId);
    function unlock(uint256 amount, uint256 userLockId) external;
    function claimFees() external returns (uint256 earned);

    function emergencyWithdraw(EmergencyWithdrawInput[] calldata emergencyWithdrawInput, address receiver) external;

    function emitFees(uint256 amount) external;

    /* ========== EVENTS ========== */

    // Events
    event UserLocked(
        address indexed user,
        uint256 indexed lockId,
        uint256 indexed lockPeriod,
        uint256 ksuAmount,
        uint256 ksuBonusAmount,
        uint256 rKSUMinted
    );
    event UserUnlocked(address indexed user, uint256 indexed lockId, uint256 ksuAmount, uint256 rKSUBurned);
    event FeesClaimed(address indexed user, uint256 amount);
    event FeesEmitted(address indexed user, uint256 amount);
    event LockPeriodAdded(uint256 indexed lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier);
    event EmergencyWithdraw(
        address indexed user, uint256 indexed lockId, uint256 ksuAmount, uint256 rKSUBurned, address receiver
    );

    /* ========== ERRORS ========== */

    error LockPeriodAlreadyExists(uint256 lockPeriod);
    error LockPeriodNotSupported(uint256 lockPeriod);
    error DepositLocked(uint256 lockPeriod);
    error InvalidUserDeposit(uint256 userLockId);
    error LockAmountShouldBeMoreThanZero();
    error UnlockAmountShouldBeMoreThanZero();
    error UserUnlockAmountTooHigh(uint256 userLockId, uint256 lockAmount, uint256 requestedUnlockAmount);
}
