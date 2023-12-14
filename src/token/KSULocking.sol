// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "./xKSU.sol";
import "./interfaces/IKSULocking.sol";
import "../shared/Constants.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";


import "lib/forge-std/src/console2.sol";

contract KSULocking is IKSULocking, xKSU {
    using SafeERC20 for IERC20;

    error LockPeriodNotSupported(uint256 lockPeriod);

    struct LockDetails {
        uint256 xKSUMultiplier;
        bool isActive;
    }

    uint256 private constant REWARDS_PRECISION = 1e24;

    IERC20 public ksuToken;
    IERC20 public feeToken;
    
    // global reward details
    uint256 public accumulatedRewardsPerShare;

    mapping(address => uint256) public rewards;
    mapping(address => uint256) public rewardDebt;

    mapping(address => UserLock[]) public userLocks;
    mapping(uint256 => LockDetails) public lockDetailsMapping;

    function initialize(IERC20 ksuToken_, IERC20 feeToken_) external initializer {
        _initializeXKSU();
        ksuToken = ksuToken_;
        feeToken = feeToken_;
    }

    /**
     * @notice Add period lock details.
     * @dev TODO: Only owner can call this function.
     * @param lockPeriod in seconds
     * @param xKSUMultiplier xKSU multiplier for the lock period
     */
    function addLockPeriod(uint256 lockPeriod, uint256 xKSUMultiplier) external {
        lockDetailsMapping[lockPeriod] = LockDetails(xKSUMultiplier, true);
    }

    /**
     * @notice Lock KSU token for a period of time.
     * @dev User must approve KSU token before calling this function.
     * @param amount KSU token amount to lock
     * @param lockPeriod in seconds
     * @return userLockId lock id
     */
    function lock(uint256 amount, uint256 lockPeriod) external returns (uint256 userLockId) {
        return _lock(amount, lockPeriod);
    }

    /**
     * @notice Lock KSU token for a period of time.
     * @dev User must approve KSU token before calling this function.
     * @param amount KSU token amount to lock
     * @param lockPeriod in seconds
     * @return userLockId lock id
     */
    function _lock(uint256 amount, uint256 lockPeriod) private returns (uint256 userLockId) {
        if (!lockDetailsMapping[lockPeriod].isActive) {
            revert LockPeriodNotSupported(lockPeriod);
        }

        // calculate current user rewards
        _updateUserRewards(msg.sender);

        // transfer KSU token from user
        ksuToken.transferFrom(msg.sender, address(this), amount);

        // mint xKSU
        uint256 xKSUAmount = amount * lockDetailsMapping[lockPeriod].xKSUMultiplier / FULL_PERCENT;
        _mint(msg.sender, xKSUAmount);

        // add user lock details
        userLockId = userLocks[msg.sender].length;
        userLocks[msg.sender].push(UserLock(amount, xKSUAmount, block.timestamp, lockPeriod));

        // update user reward details
        rewardDebt[msg.sender] = balanceOf(msg.sender) * accumulatedRewardsPerShare / REWARDS_PRECISION;
    }

    function unlock(uint256 amount, uint256 userLockId) external {
        // check if lock is ok and unlocked

        // burn xKSU

        // update reward details

        // transfer KSU token to user
        revert("0");
    }

    function emitFees(uint256 amount) external {
        feeToken.safeTransferFrom(msg.sender, address(this), amount);

        // update reward details
        _updatePoolRewards(amount);
        console2.log("accumulatedRewardsPerShare", accumulatedRewardsPerShare);
    }

    function _updatePoolRewards(uint256 newRewards) private {
        console2.log("totalSupply()", totalSupply());
        console2.log("newRewards", newRewards);
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
        
        console2.log("earned", earned);
        rewards[user] += earned;
    }

    function claimFees() external returns (uint256 earned) {
        _updateUserRewards(msg.sender);

        earned = rewards[msg.sender];

        rewards[msg.sender] = 0;

        feeToken.safeTransfer(msg.sender, earned);
    }
}
