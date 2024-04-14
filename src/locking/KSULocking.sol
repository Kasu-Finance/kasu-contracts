// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./rKSU.sol";
import "./interfaces/IKSULocking.sol";
import "../core/Constants.sol";
import "../shared/access/KasuAccessControllable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../shared/AddressLib.sol";

contract KSULocking is IKSULocking, rKSU, KasuAccessControllable {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20Permit;

    uint256 private constant REWARDS_PRECISION = 1e24;

    address private _ksuBonusTokens;

    // ERC20 tokens
    ERC20Permit private _ksuToken;
    IERC20 private _feeToken;

    mapping(address => uint256) public userTotalDeposits;
    mapping(address => UserLock[]) private _userLocks;
    mapping(uint256 => LockPeriodDetails) private _lockDetails;

    // Global reward attributes
    uint256 private _accumulatedRewardsPerShare;
    mapping(address => uint256) private _rewards;
    mapping(address => uint256) private _rewardDebt;

    /* ========== CONSTRUCTOR ========== */

    constructor(IKasuController controller_) KasuAccessControllable(controller_) {}

    /* ========== INITIALIZER ========== */

    function initialize(ERC20Permit ksuToken_, IERC20 feeToken_) external initializer {
        AddressLib.checkIfZero(address(ksuToken_));
        AddressLib.checkIfZero(address(feeToken_));

        _initializeRKSU();
        _ksuToken = ksuToken_;
        _feeToken = feeToken_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function userLock(address user, uint256 userLockId) external view returns (UserLock memory) {
        return _userLocks[user][userLockId];
    }

    function lockDetails(uint256 lockPeriod) external view returns (LockPeriodDetails memory) {
        return _lockDetails[lockPeriod];
    }

    /**
     * @dev See {IKSULocking-rewards}.
     */
    function rewards(address user) external view returns (uint256) {
        return _rewards[user] + _userRewards(user);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @dev See {IKSULocking-addLockPeriod}.
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
     * @dev See {IKSULocking-lock}.
     */
    function lock(uint256 amount, uint256 lockPeriod) external whenNotPaused returns (uint256 userLockId) {
        return _lock(amount, lockPeriod);
    }

    /**
     * @dev See {IKSULocking-lockWithPermit}.
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
     * @dev See {IKSULocking-unlock}.
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
     * @dev See {IKSULocking-emitFees}.
     */
    function emitFees(uint256 amount) external whenNotPaused {
        _feeToken.safeTransferFrom(msg.sender, address(this), amount);

        // update reward details
        _updatePoolRewards(amount);

        // emit event
        emit FeesEmitted(msg.sender, amount);
    }

    /**
     * @dev See {IKSULocking-claimFees}.
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
     * @dev See {IKSULocking-emergencyWithdraw}.
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
     * @dev See {IKSULocking-setKSULockBonus}.
     */
    function setKSULockBonus(address ksuBonusTokens_) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(ksuBonusTokens_);
        _ksuBonusTokens = ksuBonusTokens_;
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
