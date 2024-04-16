// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IKSULocking.sol";
import "../shared/access/KasuAccessControllable.sol";
import "./rKSU.sol";
import "../core/Constants.sol";
import "../shared/AddressLib.sol";

/**
 * @title KSULocking contract
 * @notice Contract to lock KSU tokens for a period of time and earn rewards.
 * @dev KSU Lockers earn instant bonus rewards in KSU tokens until initial bonus tokens are depleted.
 * When locking users receive non-transferable rKSU tokens.
 * Generally the longer the lock period the more rKSU tokens are minted to the KSU Locker.
 * Users get emitted collected platform fees in USDC based on how much rKSU they hold.
 * rKSU holders can claim their USDC rewards at any time.
 * If the KSU Locker is also a Liquidity Provider, their rKSU balance is used to calculate their loyalty level.
 */
contract KSULocking is IKSULocking, rKSU, KasuAccessControllable {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20Permit;

    /// @dev USDC rewards precision multiplier.
    uint256 private constant REWARDS_PRECISION = 1e24;

    /// @dev KSU token address.
    ERC20Permit private _ksuToken;

    /// @dev USDC token address.
    IERC20 private _feeToken;

    /// @dev Ksu bonus tokens address.
    address private _ksuBonusTokens;

    /// @notice User total KSU locked amount.
    mapping(address user => uint256 totalKsuLocked) public userTotalDeposits;

    /// @dev User lock details
    mapping(address locker => UserLock[] userLocks) private _userLocks;

    /// @dev Lock period details
    mapping(uint256 lockPeriod => LockPeriodDetails lockDetails) private _lockDetails;

    // Global reward attributes
    /// @dev Accumulated rewards per share.
    uint256 private _accumulatedRewardsPerShare;
    /// @dev User rewards.
    mapping(address => uint256) private _rewards;
    /// @dev User reward debt.
    mapping(address => uint256) private _rewardDebt;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor
     * @param controller_ Kasu controller address.
     */
    constructor(IKasuController controller_) KasuAccessControllable(controller_) {}

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the KSULocking contract.
     * @param ksuToken_ KSU token address.
     * @param feeToken_ USDC token address.
     */
    function initialize(ERC20Permit ksuToken_, IERC20 feeToken_) external initializer {
        AddressLib.checkIfZero(address(ksuToken_));
        AddressLib.checkIfZero(address(feeToken_));

        __rKSU__init();
        _ksuToken = ksuToken_;
        _feeToken = feeToken_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Returns lock details for a specific lock period.
     * @param lockPeriod Lock period in seconds.
     * @return LockPeriodDetails Lock period details.
     */
    function lockDetails(uint256 lockPeriod) external view returns (LockPeriodDetails memory) {
        return _lockDetails[lockPeriod];
    }

    /**
     * @notice Returns user lock details for a specific lock id.
     * @param user User address.
     * @param userLockId User lock id.
     * @return UserLock User lock details.
     */
    function userLock(address user, uint256 userLockId) external view returns (UserLock memory) {
        return _userLocks[user][userLockId];
    }

    /**
     * @notice Returns user's pending USDC reward amount.
     * @param user User address.
     * @return User's pending USDC reward amount.
     */
    function rewards(address user) external view returns (uint256) {
        return _rewards[user] + _userRewards(user);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Sets the KSU Bonus Tokens contract address.
     * @param ksuBonusTokens_ KSU Bonus Tokens contract address.
     */
    function setKSULockBonus(address ksuBonusTokens_) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(ksuBonusTokens_);
        _ksuBonusTokens = ksuBonusTokens_;
    }

    /**
     * @notice Add period lock details.
     * @param lockPeriod Lock period in seconds.
     * @param rKSUMultiplier rKSU multiplier for the lock period.
     */
    function addLockPeriod(uint256 lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier)
        external
        whenNotPaused
        onlyAdmin
    {
        if (_lockDetails[lockPeriod].isActive) {
            revert LockPeriodAlreadyExists(lockPeriod);
        }

        _lockDetails[lockPeriod] = LockPeriodDetails(rKSUMultiplier, ksuBonusMultiplier, true);
        emit LockPeriodAdded(lockPeriod, rKSUMultiplier, ksuBonusMultiplier);
    }

    /**
     * @notice Lock KSU token for a period of time.
     * @dev User must approve KSU token before calling this function.
     * @param amount KSU token amount to lock.
     * @param lockPeriod Lock period to lock to.
     * @return userLockId Id of the lock.
     */
    function lock(uint256 amount, uint256 lockPeriod) external whenNotPaused returns (uint256 userLockId) {
        return _lock(amount, lockPeriod);
    }

    /**
     * @notice Lock KSU token for a period of time with signed KSU allowance.
     * @param amount KSU token amount to lock.
     * @param lockPeriod Lock period to lock to.
     * @param ksuPermit KSU token permit payload.
     * @return userLockId Id of the lock.
     */
    function lockWithPermit(uint256 amount, uint256 lockPeriod, ERC20PermitPayload calldata ksuPermit)
        external
        whenNotPaused
        returns (uint256)
    {
        IERC20Permit(address(_ksuToken)).permit(
            msg.sender, address(this), ksuPermit.value, ksuPermit.deadline, ksuPermit.v, ksuPermit.r, ksuPermit.s
        );

        return _lock(amount, lockPeriod);
    }

    /**
     * @notice Unlock KSU tokens.
     * @dev Locking period must be over.
     * @param unlockAmount KSU token amount to unlock.
     * @param userLockId lock id to unlock from.
     */
    function unlock(uint256 unlockAmount, uint256 userLockId) external whenNotPaused {
        // check if lock is unlocked
        UserLock storage userLock_ = _userLocks[msg.sender][userLockId];

        uint256 unlockTime = userLock_.startTime + userLock_.lockPeriod;

        if (unlockTime > block.timestamp) {
            revert DepositLocked(userLockId);
        }

        uint256 rKSUBurned = _withdrawUserLockId(msg.sender, userLockId, unlockAmount, msg.sender);

        // emit event
        emit UserUnlocked(msg.sender, userLockId, unlockAmount, rKSUBurned);
    }

    /**
     * @notice Called by user to claim all his accrued USDC fees.
     * @return earned User's claimed USDC reward amount.
     */
    function claimFees() external whenNotPaused returns (uint256 earned) {
        _updateUserRewards(msg.sender);

        earned = _rewards[msg.sender];

        _rewards[msg.sender] = 0;

        _updateUserRewardDebt(msg.sender);

        _feeToken.safeTransfer(msg.sender, earned);

        emit FeesClaimed(msg.sender, earned);
    }

    /**
     * @notice Called by admin in case of emergency to unlock and claim KSU tokens from users.
     * @param emergencyWithdrawInput Emergency withdraw input array.
     * @param receiver Receiver of SKU tokens address.
     */
    function emergencyWithdraw(EmergencyWithdrawInput[] calldata emergencyWithdrawInput, address receiver)
        external
        onlyAdmin
    {
        for (uint256 i = 0; i < emergencyWithdrawInput.length; ++i) {
            _emergencyWithdraw(
                emergencyWithdrawInput[i].user,
                emergencyWithdrawInput[i].lockId,
                emergencyWithdrawInput[i].withdrawAmount,
                receiver
            );
        }
    }

    /**
     * @notice Emitting USDC fees to the locking contracts.
     * @dev Anyone can call this function.
     * Caller must approve USDC token before calling this function.
     * @param amount amount of fees to emit.
     */
    function emitFees(uint256 amount) external whenNotPaused {
        _feeToken.safeTransferFrom(msg.sender, address(this), amount);

        // update reward details
        _updatePoolRewards(amount);

        // emit event
        emit FeesEmitted(msg.sender, amount);
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _userRewards(address user) private view returns (uint256) {
        return balanceOf(user) * _accumulatedRewardsPerShare / REWARDS_PRECISION - _rewardDebt[user];
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _emergencyWithdraw(address user, uint256 userLockId, uint256 withdrawAmount, address receiver) internal {
        uint256 rKSUBurned = _withdrawUserLockId(user, userLockId, withdrawAmount, receiver);

        emit EmergencyWithdraw(user, userLockId, withdrawAmount, rKSUBurned, receiver);
    }

    function _withdrawUserLockId(address user, uint256 userLockId, uint256 withdrawAmount, address transferTo)
        internal
        returns (uint256)
    {
        // check if lock exists
        UserLock storage userLock_ = _userLocks[user][userLockId];

        if (userLock_.amount == 0) {
            revert InvalidUserDeposit(userLockId);
        }

        if (withdrawAmount == 0) {
            revert UnlockAmountShouldBeMoreThanZero();
        }

        if (userLock_.amount < withdrawAmount) {
            revert UserUnlockAmountTooHigh(userLockId, userLock_.amount, withdrawAmount);
        }

        // calculate current user rewards
        _updateUserRewards(user);

        // burn rKSU
        uint256 amountRemaining = userLock_.amount - withdrawAmount;
        uint256 rKSURemaining = amountRemaining * userLock_.rKSUMultiplier / FULL_PERCENT;
        uint256 rKSUBurned = userLock_.rKSUAmount - rKSURemaining;
        _burn(user, rKSUBurned);

        // update reward details
        userLock_.amount = amountRemaining;
        userLock_.rKSUAmount = rKSURemaining;
        userTotalDeposits[user] -= withdrawAmount;

        // update user reward debt
        _updateUserRewardDebt(user);

        // transfer KSU token to receiver
        _ksuToken.safeTransfer(transferTo, withdrawAmount);

        return rKSUBurned;
    }

    function _lock(uint256 amount, uint256 lockPeriod) private returns (uint256 userLockId) {
        if (!_lockDetails[lockPeriod].isActive) {
            revert LockPeriodNotSupported(lockPeriod);
        }

        if (amount == 0) {
            revert LockAmountShouldBeMoreThanZero();
        }

        // transfer KSU token from user
        _ksuToken.safeTransferFrom(msg.sender, address(this), amount);

        // calculate current user rewards
        _updateUserRewards(msg.sender);

        // transfer bonus KSU token to user
        uint256 ksuBonusMultiplier = _lockDetails[lockPeriod].ksuBonusMultiplier;
        uint256 ksuCalculatedBonusAmount = amount * ksuBonusMultiplier / FULL_PERCENT;
        uint256 ksuBonusAmount = _bonusKSU(ksuCalculatedBonusAmount);
        uint256 lockAmount = amount + ksuBonusAmount;

        // mint rKSU
        uint256 rKSUMultiplier = _lockDetails[lockPeriod].rKSUMultiplier;
        uint256 rKSUAmount = lockAmount * rKSUMultiplier / FULL_PERCENT;
        _mint(msg.sender, rKSUAmount);

        // add user lock details
        userLockId = _userLocks[msg.sender].length;
        _userLocks[msg.sender].push(UserLock(lockAmount, rKSUAmount, rKSUMultiplier, block.timestamp, lockPeriod));
        userTotalDeposits[msg.sender] += lockAmount;

        // update user reward debt
        _updateUserRewardDebt(msg.sender);

        // emit event
        emit UserLocked(msg.sender, userLockId, lockPeriod, amount, ksuBonusAmount, rKSUAmount);
    }

    function _updatePoolRewards(uint256 newRewards) private {
        if (totalSupply() == 0) {
            return;
        }

        _accumulatedRewardsPerShare += newRewards * REWARDS_PRECISION / totalSupply();
    }

    function _updateUserRewards(address user) private {
        uint256 earned = _userRewards(user);

        _rewards[user] += earned;
    }

    function _updateUserRewardDebt(address user) private {
        _rewardDebt[user] = balanceOf(user) * _accumulatedRewardsPerShare / REWARDS_PRECISION;
    }

    /**
     * @notice Send bonus KSU tokens to this contract if available.
     */
    function _bonusKSU(uint256 requestedAmount) private returns (uint256 ksuSentAmount) {
        uint256 bonusAmount = _ksuToken.balanceOf(_ksuBonusTokens);
        uint256 bonusAllowance = _ksuToken.allowance(_ksuBonusTokens, address(this));

        if (bonusAmount > bonusAllowance) {
            bonusAmount = bonusAllowance;
        }

        if (bonusAmount > requestedAmount) {
            ksuSentAmount = requestedAmount;
        } else {
            ksuSentAmount = bonusAmount;
        }

        if (ksuSentAmount > 0) {
            _ksuToken.safeTransferFrom(_ksuBonusTokens, address(this), ksuSentAmount);
        }
    }
}
