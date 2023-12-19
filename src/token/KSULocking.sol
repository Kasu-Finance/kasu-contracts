// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./rKSU.sol";
import "./interfaces/IKSULocking.sol";
import "../shared/Constants.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract KSULocking is IKSULocking, rKSU {
    using SafeERC20 for IERC20;

    uint256 private constant REWARDS_PRECISION = 1e24;

    // ERC20 tokens
    IERC20 public ksuToken;
    IERC20 public feeToken;

    // Global reward attributes
    struct LockDetails {
        uint256 rKSUMultiplier;
        bool isActive;
    }

    uint256 public accumulatedRewardsPerShare;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public rewardDebt;

    mapping(address => UserLock[]) public userLocks;
    mapping(uint256 => LockDetails) public lockDetailsMapping;

    function initialize(IERC20 ksuToken_, IERC20 feeToken_) external initializer {
        _initializeRKSU();
        ksuToken = ksuToken_;
        feeToken = feeToken_;
    }

    // ### Public Interface ###

    /**
     * @notice Add period lock details
     * @dev TODO: Only owner can call this function
     * @param lockPeriod in seconds
     * @param rKSUMultiplier xKSU multiplier for the lock period
     */
    function addLockPeriod(uint256 lockPeriod, uint256 rKSUMultiplier) external {
        lockDetailsMapping[lockPeriod] = LockDetails(rKSUMultiplier, true);
    }

    /**
     * @notice Lock KSU token for a period of time
     * @dev User must approve KSU token before calling this function
     * @param amount KSU token amount to lock
     * @param lockPeriod in seconds
     * @return userLockId lock id
     */
    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId) {
        return _lock(amount, lockPeriod);
    }


    /**
     * @notice Unlock KSU token. Locking period must over
     * @param unlockAmount KSU token amount to unlock
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
    }

    /**
     * @notice Adding USDC to the locking contracts
     * @dev Must approve USDC token before calling this function
     * @param amount amount of fees to add
     */
    function emitFees(uint256 amount) external {
        feeToken.safeTransferFrom(msg.sender, address(this), amount);

        // update reward details
        _updatePoolRewards(amount);
    }

    /**
     * @notice Called by user to get all his USDC fees
     */
    function claimFees() external returns (uint256 earned) {
        _updateUserRewards(msg.sender);

        earned = rewards[msg.sender];

        rewards[msg.sender] = 0;

        feeToken.safeTransfer(msg.sender, earned);
    }

    function getRewards() public view returns (uint256) {
        return rewards[msg.sender] + _getUserRewards(msg.sender);
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

        // mint xKSU
        uint256 rKSUMultiplier = lockDetailsMapping[lockPeriod].rKSUMultiplier;
        uint256 rKSUAmount = amount * rKSUMultiplier / FULL_PERCENT;
        _mint(msg.sender, rKSUAmount);

        // add user lock details
        userLockId = userLocks[msg.sender].length;
        userLocks[msg.sender].push(UserLock(amount, rKSUAmount, rKSUMultiplier, block.timestamp, lockPeriod));

        // update user reward details
        rewardDebt[msg.sender] = balanceOf(msg.sender) * accumulatedRewardsPerShare / REWARDS_PRECISION;
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

}
