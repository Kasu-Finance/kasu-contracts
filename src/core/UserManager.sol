// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IUserManager.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IUserLoyaltyRewards.sol";
import "./interfaces/lendingPool/ILendingPool.sol";
import "./interfaces/lendingPool/IPendingPool.sol";
import "./interfaces/lendingPool/ILendingPoolErrors.sol";
import "../locking/interfaces/IKSULocking.sol";
import "../shared/CommonErrors.sol";
import "./Constants.sol";
import "../shared/AddressLib.sol";

/**
 * @title User Manager Contract
 * @notice This contract is primarily used to calculate a user loyalty level for the current epoch.
 */
contract UserManager is IUserManager, Initializable {
    /// @notice System variables contract.
    ISystemVariables public immutable systemVariables;

    /// @notice KSU locking contract.
    IKSULocking public immutable ksuLocking;

    /// @notice User loyalty rewards contract.
    IUserLoyaltyRewards public immutable userLoyaltyRewards;

    /// @notice Lending pool manager address.
    address public lendingPoolManager;

    /// @notice Is address a Kasu user.
    mapping(address => bool) public isUser;

    /// @notice Is user part of lending pool.
    mapping(address lendingPool => mapping(address user => bool)) public isUserPartOfLendingPool;

    /// @notice All active Kaus users array.
    /// @dev Users are only removed by manually calling updateUserLendingPools.
    address[] private _allUsers;

    /// @notice User active lending pools.
    /// @dev Lending pools of a user are only removed by manually calling updateUserLendingPools.
    mapping(address user => address[] lendingPools) private _userLendingPools;

    /// @dev Calculated user epoch loyalty level.
    mapping(address user => mapping(uint256 epochId => uint8 loyaltyLevel)) private _userEpochLoyaltyLevel;

    /// @dev Details of processing user loyalty levels for the epoch.
    mapping(uint256 epochId => EpochUserLoyaltyProcessing) private _epochUserLoyaltyProcessing;

    struct LoyaltyGlobalParameters {
        uint256 currentEpoch;
        uint256 ksuPrice;
        uint256[] loyaltyThresholds;
    }

    /**
     * @notice Constructor.
     * @param systemVariables_ System variables contract.
     * @param ksuLocking_ KSU locking contract.
     * @param userLoyaltyRewards_ User loyalty rewards contract.
     */
    constructor(ISystemVariables systemVariables_, IKSULocking ksuLocking_, IUserLoyaltyRewards userLoyaltyRewards_) {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(address(ksuLocking_));
        AddressLib.checkIfZero(address(userLoyaltyRewards_));

        systemVariables = systemVariables_;
        ksuLocking = ksuLocking_;
        userLoyaltyRewards = userLoyaltyRewards_;

        _disableInitializers();
    }

    /**
     * @notice Initialize the contract.
     * @param lendingPoolManager_ Lending pool manager address.
     */
    function initialize(address lendingPoolManager_) external initializer {
        AddressLib.checkIfZero(lendingPoolManager_);
        lendingPoolManager = lendingPoolManager_;
    }

    /**
     * @notice Get the calculated user epoch loyalty level.
     * @dev If the loylty level is not calculated for the epoch it will return 0.
     * @param user The address of the user.
     * @param epoch The epoch number.
     * @return The calculated user's loyalty level for the epoch.
     */
    function getCalculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view returns (uint8) {
        return _userEpochLoyaltyLevel[user][epoch];
    }

    /**
     * @notice Get the epoch user loyalty processing details.
     * @param epoch The epoch number.
     * @return The epoch user loyalty processing details.
     */
    function getEpochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory) {
        return _epochUserLoyaltyProcessing[epoch];
    }

    /**
     * @notice Get all user active lending pools.
     * @dev The user lending pools are only removed by manually calling updateUserLendingPools.
     * @param user The address of the user.
     * @return lendingPools The user lending pools.
     */
    function getUserLendingPools(address user) external view returns (address[] memory lendingPools) {
        return _userLendingPools[user];
    }

    /**
     * @notice Get all active users.
     * @dev Users are only removed by manually calling updateUserLendingPools.
     * @return The array of all active users.
     */
    function getAllUsers() external view returns (address[] memory) {
        return _allUsers;
    }

    /**
     * @notice Get the total pending and active deposited amount.
     * @dev Returns the amount including pending deposits for the next epoch.
     * @param user The address of the user.
     * @return activeDepositAmount The active deposited amount for the user.
     * @return pendingDepositAmount The pending deposited amount for the user.
     */
    function getUserTotalPendingAndActiveDepositedAmount(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        uint256 nextEpoch = systemVariables.getCurrentEpochNumber() + 1;

        (activeDepositAmount, pendingDepositAmount) = _getUserTotalPendingAndActiveDepositedAmount(user, nextEpoch);
    }

    /**
     * @notice Get the total pending and active deposited amount for the user for the current epoch.
     * @dev Only returns the amount that will be used to calculate the user's loyalty level this clearing period.
     * @param user The address of the user.
     * @return activeDepositAmount The active deposited amount for the user for the current epoch.
     * @return pendingDepositAmount The pending deposited amount for the user for the current epoch.
     */
    function getUserTotalPendingAndActiveDepositedAmountForCurrentEpoch(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        (activeDepositAmount, pendingDepositAmount) = _getUserTotalPendingAndActiveDepositedAmount(user, currentEpoch);
    }

    /**
     * @notice Check if the user has rKSU.
     * @param user The address of the user.
     * @return True if the user has any rKSU.
     */
    function hasUserRKSU(address user) public view returns (bool) {
        return ksuLocking.balanceOf(user) > 0;
    }

    /**
     * @notice Check if the user can deposit in the junior tranche.
     * @dev
     * If the system variable is set to true, the user can only deposit in the junior tranche if he has any rKSU balance.
     * If the system variable is set to false, the user can always deposit in the junior tranche.
     * @param user The address of the user.
     * @return True if the user can deposit in the junior tranche.
     */
    function canUserDepositInJuniorTranche(address user) external view returns (bool) {
        if (systemVariables.getUserCanOnlyDepositToJuniorTrancheWhenHeHasRKSU()) {
            return hasUserRKSU(user);
        } else {
            return true;
        }
    }

    /**
     * @notice Batch calculate user loyalty levels for the current epoch.
     * @dev
     * This function is used to calculate user loyalty levels in batches.
     * The function will calculate the loyalty level for the user and update the user's loyalty level for the current epoch.
     * Can only be called during the clearing time.
     * @param batchSize The size of the batch.
     */
    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external {
        if (!systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (batchSize == 0) {
            return;
        }

        LoyaltyGlobalParameters memory params = _getLoyaltyParameters();

        // initialize user loyalty processing for the epoch if it has not started yet
        if (!_epochUserLoyaltyProcessing[params.currentEpoch].didStart) {
            _epochUserLoyaltyProcessing[params.currentEpoch].userCount = _allUsers.length;
            _epochUserLoyaltyProcessing[params.currentEpoch].didStart = true;
        }

        uint256 startUser = _epochUserLoyaltyProcessing[params.currentEpoch].processedUsersCount;
        uint256 endUser = startUser + batchSize;

        if (endUser > _epochUserLoyaltyProcessing[params.currentEpoch].userCount) {
            endUser = _epochUserLoyaltyProcessing[params.currentEpoch].userCount;
        }

        if (startUser == endUser) {
            return;
        }

        for (uint256 i = startUser; i < endUser; ++i) {
            address user = _allUsers[i];

            (uint8 loyaltyLevel, uint256 activeDepositAmount,) = _userLoyaltyLevel(user, params);

            // update user loyalty level
            _userEpochLoyaltyLevel[user][params.currentEpoch] = loyaltyLevel;

            // call user loyalty rewards contract to calculate and emit user loyalty rewards for the epoch
            userLoyaltyRewards.emitUserLoyaltyReward(user, params.currentEpoch, loyaltyLevel, activeDepositAmount);

            emit UserLoyaltyLevelUpdated(user, params.currentEpoch, loyaltyLevel);
        }

        _epochUserLoyaltyProcessing[params.currentEpoch].processedUsersCount = endUser;

        if (_epochUserLoyaltyProcessing[params.currentEpoch].userCount == endUser) {
            emit UserLoyaltyLevelsForEpochProcessed(params.currentEpoch, endUser);
        }
    }

    /**
     * @notice Check if the user loyalty levels are processed for the epoch.
     * @param epoch The epoch number.
     * @return True if the user loyalty levels are processed for the epoch.
     */
    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view returns (bool) {
        return _epochUserLoyaltyProcessing[epoch].didStart
            && _epochUserLoyaltyProcessing[epoch].processedUsersCount == _epochUserLoyaltyProcessing[epoch].userCount;
    }

    function _getLoyaltyParameters() private view returns (LoyaltyGlobalParameters memory params) {
        params.currentEpoch = systemVariables.getCurrentEpochNumber();
        params.ksuPrice = systemVariables.ksuEpochTokenPrice();
        params.loyaltyThresholds = systemVariables.loyaltyThresholds();
    }

    /**
     * @notice Calculate the user loyalty level for the current epoch.
     * @param user The address of the user.
     * @return currentEpoch The current epoch number.
     * @return loyaltyLevel The user's loyalty level.
     */
    function getUserLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint8 loyaltyLevel) {
        LoyaltyGlobalParameters memory params = _getLoyaltyParameters();
        currentEpoch = params.currentEpoch;
        (loyaltyLevel,,) = _userLoyaltyLevel(user, params);
    }

    function _userLoyaltyLevel(address user, LoyaltyGlobalParameters memory params)
        private
        view
        returns (uint8 loyaltyLevel, uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        // get user deposit amount for the current epoch
        (activeDepositAmount, pendingDepositAmount) =
            _getUserTotalPendingAndActiveDepositedAmount(user, params.currentEpoch);
        uint256 userDepositAmount = activeDepositAmount + pendingDepositAmount;

        // get user rKSU balance
        uint256 userRKSU = ksuLocking.balanceOf(user);

        // calculate rKSU in asset (USDC)
        uint256 rKSUInUSDC = _getRKSUInUSDC(userRKSU, params.ksuPrice);

        // calculate user rKSU vs user deposit amount
        uint256 rKSUDepositRatio;
        if (userDepositAmount > 0) {
            rKSUDepositRatio = rKSUInUSDC * FULL_PERCENT / userDepositAmount;
        } else if (userRKSU > 0) {
            // if user has rKSU and no deposit amount his loyalty level is max
            rKSUDepositRatio = type(uint256).max;
        }

        // calculate user loyalty level
        for (uint256 i; i < params.loyaltyThresholds.length; ++i) {
            if (rKSUDepositRatio >= params.loyaltyThresholds[i]) {
                loyaltyLevel++;
            } else {
                break;
            }
        }
    }

    function _getUserTotalPendingAndActiveDepositedAmount(address user, uint256 epochId)
        private
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        // loop through all user lending pools
        for (uint256 i; i < _userLendingPools[user].length; ++i) {
            (uint256 poolActiveDepositAmount, uint256 poolPendingDepositAmount) =
                _getUserLendingPoolActiveAndPendingBalance(user, _userLendingPools[user][i], epochId);

            activeDepositAmount += poolActiveDepositAmount;
            pendingDepositAmount += poolPendingDepositAmount;
        }
    }

    function _getUserLendingPoolActiveAndPendingBalance(address user, address lendingPool, uint256 epochId)
        private
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        activeDepositAmount = ILendingPool(lendingPool).userBalance(user);

        // get user pending deposit amount
        IPendingPool pendingPool = IPendingPool(ILendingPool(lendingPool).pendingPool());
        pendingDepositAmount = pendingPool.userPendingDepositAmount(user, epochId);
    }

    function _getRKSUInUSDC(uint256 rKSUAmount, uint256 ksuPrice) internal pure returns (uint256 rKSUInUSDC) {
        // NOTE: 1e12 is the difference in decimal places between rKSU and USDC
        rKSUInUSDC = rKSUAmount * ksuPrice / KSU_PRICE_MULTIPLIER / 1e12;
    }

    /**
     * @notice Notices the user manager contract of a user requesting a deposit.
     * @dev
     * This function is used to add user to the all users array and user lending pools array.
     * Can only be called by the lending pool manager.
     * @param user The address of the user.
     * @param lendingPool The address of the lending pool.
     */
    function userRequestedDeposit(address user, address lendingPool) external {
        if (msg.sender != lendingPoolManager) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }

        // add user to all users if it is not already added
        if (!isUser[user]) {
            _allUsers.push(user);
            isUser[user] = true;
        }

        // add lending pools to user lending pools array if it is not already added
        if (!isUserPartOfLendingPool[lendingPool][user]) {
            _userLendingPools[user].push(lendingPool);
            isUserPartOfLendingPool[lendingPool][user] = true;
        }
    }

    /**
     * @notice Update users and user lending pools arrays. Removes user from all users if it has no balance in lending pools left.
     * @dev
     * This function is used to remove users and its lending pools and from arrays if balance is 0.
     * Processing of users and user lending pools is done in reverse order. From `toIndex` to `fromIndex`.
     * `fromIndex` is strictly less or equal to `toIndex`.
     * @param fromIndex The starting index to process of the all users array.
     * @param toIndex The ending index to process of the all users array. Including the desired processed index.
     */
    function updateUserLendingPools(uint256 fromIndex, uint256 toIndex) external {
        if (systemVariables.isClearingTime()) {
            revert CannotExecuteDuringClearingTime();
        }

        if (_allUsers.length == 0) {
            return;
        }

        if (toIndex >= _allUsers.length) {
            unchecked {
                toIndex = _allUsers.length - 1;
            }
        }

        if (toIndex < fromIndex) {
            revert BadUserIndex();
        }

        // include the pending deposit amount for the next epoch as well
        uint256 nextEpoch = systemVariables.getCurrentEpochNumber() + 1;

        while (fromIndex <= toIndex) {
            address user = _allUsers[toIndex];
            uint256 userLendingPoolsIndex = _userLendingPools[user].length;

            // check every user lending pool and remove if balance is 0
            while (true) {
                if (userLendingPoolsIndex == 0) {
                    break;
                }

                unchecked {
                    --userLendingPoolsIndex;
                }

                (uint256 activeDepositAmount, uint256 pendingDepositAmount) = _getUserLendingPoolActiveAndPendingBalance(
                    user, _userLendingPools[user][userLendingPoolsIndex], nextEpoch
                );

                // if user has no balance in lending pool remove it from user lending pools
                if (activeDepositAmount == 0 && pendingDepositAmount == 0) {
                    _removeLendingPoolFromUser(user, userLendingPoolsIndex);
                }
            }

            // if user has no lending pools left remove it from all users
            if (_userLendingPools[user].length == 0) {
                _removeUserFromAllUsers(toIndex);
            }

            if (toIndex == 0) {
                break;
            }

            unchecked {
                --toIndex;
            }
        }
    }

    function _removeLendingPoolFromUser(address user, uint256 userLendingPoolIndex) internal {
        _userLendingPools[user][userLendingPoolIndex] = _userLendingPools[user][_userLendingPools[user].length - 1];
        _userLendingPools[user].pop();
    }

    function _removeUserFromAllUsers(uint256 userIndex) internal {
        isUser[_allUsers[userIndex]] = false;
        _allUsers[userIndex] = _allUsers[_allUsers.length - 1];
        _allUsers.pop();
    }
}
