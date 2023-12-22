// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./rKSU.sol";
import "./interfaces/IKSULocking.sol";
import "../shared/Constants.sol";
import "../shared/access/KasuAccessControllable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract KSULocking is IKSULocking, rKSU, KasuAccessControllable {
    using SafeERC20 for IERC20;

    uint256 private constant REWARDS_PRECISION = 1e24;

    address public ksuBonusTokens;

    // ERC20 tokens
    IERC20 public ksuToken;
    IERC20 public feeToken;

    // Global reward attributes
    struct LockDetails {
        uint256 rKSUMultiplier;
        uint256 ksuBonusMultiplier;
        bool isActive;
    }

    uint256 public accumulatedRewardsPerShare;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public rewardDebt;

    mapping(address => UserLock[]) public userLocks;
    mapping(uint256 => LockDetails) public lockDetailsMapping;

    constructor(IKasuController controller_) KasuAccessControllable(controller_) {}

    function initialize(IERC20 ksuToken_, IERC20 feeToken_) external initializer {
        _initializeRKSU();
        ksuToken = ksuToken_;
        feeToken = feeToken_;
    }

    // ### Public Interface ###

    /**
     * @dev See {IKSULocking-addLockPeriod}.
     */
    function addLockPeriod(uint256 lockPeriod, uint256 rKSUMultiplier, uint256 ksuBonusMultiplier) external onlyAdmin {
        lockDetailsMapping[lockPeriod] = LockDetails(rKSUMultiplier, ksuBonusMultiplier, true);
        emit LockPeriodAdded(lockPeriod, rKSUMultiplier, ksuBonusMultiplier);
    }

    /**
     * @dev See {IKSULocking-lock}.
     */
    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId) {
        return _lock(amount, lockPeriod);
    }

    /**
     * @dev See {IKSULocking-lockWithPermit}.
     */
    function lockWithPermit(uint256 amount, uint256 lockPeriod, ERC20Permit calldata ksuPermit)
        external
        returns (uint256)
    {
        IERC20Permit(address(ksuToken)).permit(
            msg.sender, address(this), ksuPermit.value, ksuPermit.deadline, ksuPermit.v, ksuPermit.r, ksuPermit.s
        );

        return _lock(amount, lockPeriod);
    }

    /**
     * @dev See {IKSULocking-unlock}.
     */
    function unlock(uint256 unlockAmount, uint256 userLockId) external {
        // check if lock is ok and unlocked
        UserLock storage userLock = userLocks[msg.sender][userLockId];

        if (userLock.amount == 0) {
            revert InvalidUserDeposit(userLockId);
        }

        if (userLock.amount < unlockAmount) {
            revert UserUnlockAmountTooHigh(userLockId, userLock.amount, unlockAmount);
        }

        uint256 unlockTime = userLock.startTime + userLock.lockPeriod;

        if (unlockTime > block.timestamp) {
            revert DepositLocked(userLockId);
        }

        // calculate current user rewards
        _updateUserRewards(msg.sender);

        // burn xKSU
        uint256 amountRemaining = userLock.amount - unlockAmount;
        uint256 rKSURemaining = amountRemaining * userLock.rKSUMultiplier / FULL_PERCENT;

        _burn(msg.sender, userLock.rKSUAmount - rKSURemaining);

        // update reward details
        userLock.amount = amountRemaining;
        userLock.rKSUAmount = rKSURemaining;

        // transfer KSU token to user
        ksuToken.transfer(msg.sender, unlockAmount);

        // emit event
        emit UserUnlocked(msg.sender, userLockId, unlockAmount);
    }

    /**
     * @dev See {IKSULocking-emitFees}.
     */
    function emitFees(uint256 amount) external {
        feeToken.safeTransferFrom(msg.sender, address(this), amount);

        // update reward details
        _updatePoolRewards(amount);

        // emit event
        emit FeesEmitted(msg.sender, amount);
    }

    /**
     * @dev See {IKSULocking-claimFees}.
     */
    function claimFees() external returns (uint256 earned) {
        _updateUserRewards(msg.sender);

        earned = rewards[msg.sender];

        rewards[msg.sender] = 0;

        feeToken.safeTransfer(msg.sender, earned);

        emit FeesClaimed(msg.sender, earned);
    }

    /**
     * @dev See {IKSULocking-setKSULockBonus}.
     */
    function setKSULockBonus(address ksuBonusTokens_) external {
        ksuBonusTokens = ksuBonusTokens_;
    }

    /**
     * @dev See {IKSULocking-getRewards}.
     */
    function getRewards(address user) external view returns (uint256) {
        return rewards[user] + _getUserRewards(msg.sender);
    }

    // ### Private Functions ###

    function _lock(uint256 amount, uint256 lockPeriod) private returns (uint256 userLockId) {
        if (!lockDetailsMapping[lockPeriod].isActive) {
            revert LockPeriodNotSupported(lockPeriod);
        }

        // transfer KSU token from user
        ksuToken.transferFrom(msg.sender, address(this), amount);

        // calculate current user rewards
        _updateUserRewards(msg.sender);

        // transfer bonus KSU token to user
        uint256 ksuBonusMultiplier = lockDetailsMapping[lockPeriod].ksuBonusMultiplier;
        uint256 ksuCalculatedBonusAmount = amount * ksuBonusMultiplier / FULL_PERCENT;
        uint256 ksuBonusAmount = _getBonusKSU(ksuCalculatedBonusAmount);
        uint256 lockAmount = amount + ksuBonusAmount;

        // mint xKSU
        uint256 rKSUMultiplier = lockDetailsMapping[lockPeriod].rKSUMultiplier;
        uint256 rKSUAmount = lockAmount * rKSUMultiplier / FULL_PERCENT;
        _mint(msg.sender, rKSUAmount);

        // add user lock details
        userLockId = userLocks[msg.sender].length;
        userLocks[msg.sender].push(UserLock(lockAmount, rKSUAmount, rKSUMultiplier, block.timestamp, lockPeriod));

        // update user reward details
        rewardDebt[msg.sender] = balanceOf(msg.sender) * accumulatedRewardsPerShare / REWARDS_PRECISION;

        // emit event
        emit UserLocked(msg.sender, userLockId, amount, ksuBonusAmount);
    }

    function _updatePoolRewards(uint256 newRewards) private {
        if (totalSupply() == 0) {
            return;
        }

        accumulatedRewardsPerShare += newRewards * REWARDS_PRECISION / totalSupply();
    }

    function _getUserRewards(address user) private view returns (uint256) {
        return balanceOf(user) * accumulatedRewardsPerShare / REWARDS_PRECISION - rewardDebt[user];
    }

    function _updateUserRewards(address user) private {
        uint256 earned = _getUserRewards(user);

        rewards[user] += earned;
    }

    function _getBonusKSU(uint256 requestedAmount) private returns (uint256 ksuSentAmount) {
        uint256 bonusAmount = ksuToken.balanceOf(ksuBonusTokens);
        uint256 bonusAllowance = ksuToken.allowance(ksuBonusTokens, address(this));

        if (bonusAmount > bonusAllowance) {
            bonusAmount = bonusAllowance;
        }

        if (bonusAmount > requestedAmount) {
            ksuSentAmount = requestedAmount;
        } else {
            ksuSentAmount = bonusAmount;
        }

        if (ksuSentAmount > 0) {
            ksuToken.transferFrom(ksuBonusTokens, address(this), ksuSentAmount);
        }
    }
}
