// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IUserManager.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/IUserLoyaltyRewards.sol";
import "./interfaces/lendingPool/ILendingPool.sol";
import "./interfaces/lendingPool/ILendingPoolTranche.sol";
import "./interfaces/lendingPool/IPendingPool.sol";
import "./interfaces/lendingPool/ILendingPoolErrors.sol";
import "../locking/interfaces/IKSULocking.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";

/**
 * @title User Manager Contract
 * @notice This contract is primarily used to calculate a user loyalty level for the current epoch.
 */
contract UserManager is IUserManager, Initializable {
    /// @notice System variables contract.
    ISystemVariables private immutable _systemVariables;

    /// @notice KSU locking contract.
    IKSULocking private immutable _ksuLocking;

    /// @notice User loyalty rewards contract.
    IUserLoyaltyRewards private immutable _userLoyaltyRewards;

    /// @notice Lending pool manager address.
    address private _lendingPoolManager;

    /// @notice Is address a Kasu user.
    mapping(address => bool) private _isUser;

    /// @notice Is user part of lending pool.
    mapping(address lendingPool => mapping(address user => bool)) private _isUserPartOfLendingPool;

    /// @notice All active Kasu users array.
    /// @dev Users are only removed by manually calling updateUserLendingPools.
    address[] private _allUsers;

    /// @notice User active lending pools.
    /// @dev Lending pools of a user are only removed by manually calling updateUserLendingPools.
    mapping(address user => address[] lendingPools) private _userLendingPools;

    /// @dev Calculated user epoch loyalty level.
    mapping(address user => mapping(uint256 epochId => uint8 loyaltyLevel)) private _userEpochLoyaltyLevel;

    /// @dev Details of processing user loyalty levels for the epoch.
    mapping(uint256 epochId => EpochUserLoyaltyProcessing) private _epochUserLoyaltyProcessing;

    /// @notice Count of tranches user is active in.
    mapping(address user => uint256 activeTrancheCount) private _userActiveTrancheCount;

    struct LoyaltyGlobalParameters {
        uint256 currentEpoch;
        uint256 ksuPrice;
        uint256[] loyaltyThresholds;
    }

    /* ========== CONSTRUCTOR ========== */

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

        _systemVariables = systemVariables_;
        _ksuLocking = ksuLocking_;
        _userLoyaltyRewards = userLoyaltyRewards_;

        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initialize the contract.
     * @param lendingPoolManager_ Lending pool manager address.
     */
    function initialize(address lendingPoolManager_) external initializer {
        AddressLib.checkIfZero(lendingPoolManager_);
        _lendingPoolManager = lendingPoolManager_;
    }

    /**
     * @notice Initialize the contract the second time.
     * @param users The array of users.
     * @param counts The array of user active tranche counts.
     */
    function reinitialize(address[] calldata users, uint256[] calldata counts) external reinitializer(2) {
        _batchSetUserActiveTrancheCount(users, counts);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Get the calculated user epoch loyalty level.
     * @dev If the loyalty level is not calculated for the epoch it will return 0.
     * @param user The address of the user.
     * @param epoch The epoch number.
     * @return The calculated user's loyalty level for the epoch.
     */
    function calculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view returns (uint8) {
        return _userEpochLoyaltyLevel[user][epoch];
    }

    /**
     * @notice Get the epoch user loyalty processing details.
     * @param epoch The epoch number.
     * @return The epoch user loyalty processing details.
     */
    function epochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory) {
        return _epochUserLoyaltyProcessing[epoch];
    }

    /**
     * @notice Get all user active lending pools.
     * @dev The user lending pools are only removed by manually calling updateUserLendingPools.
     * @param user The address of the user.
     * @return lendingPools The user lending pools.
     */
    function userLendingPools(address user) external view returns (address[] memory lendingPools) {
        return _userLendingPools[user];
    }

    /**
     * @notice Get the count of active users in the system.
     * @return The count of all active users.
     */
    function userCount() external view returns (uint256) {
        return _allUsers.length;
    }

    /**
     * @notice Get all active users.
     * @dev Users are only removed by manually calling updateUserLendingPools.
     * @return The array of all active users.
     */
    function allUsers() external view returns (address[] memory) {
        return _allUsers;
    }

    /**
     * @notice Get the total pending and active deposited amount.
     * @dev Returns the amount including pending deposits for the next epoch.
     * @param user The address of the user.
     * @return activeDepositAmount The active deposited amount for the user.
     * @return pendingDepositAmount The pending deposited amount for the user.
     */
    function userTotalPendingAndActiveDepositedAmount(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        uint256 nextEpoch = _systemVariables.currentEpochNumber() + 1;

        (activeDepositAmount, pendingDepositAmount) = _userTotalPendingAndActiveDepositedAmount(user, nextEpoch);
    }

    /**
     * @notice Get the total pending and active deposited amount for the user for the current epoch.
     * @dev Only returns the amount that will be used to calculate the user's loyalty level this clearing period.
     * @param user The address of the user.
     * @return activeDepositAmount The active deposited amount for the user for the current epoch.
     * @return pendingDepositAmount The pending deposited amount for the user for the current epoch.
     */
    function userTotalPendingAndActiveDepositedAmountForCurrentEpoch(address user)
        external
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        uint256 currentEpoch = _systemVariables.currentEpochNumber();

        (activeDepositAmount, pendingDepositAmount) = _userTotalPendingAndActiveDepositedAmount(user, currentEpoch);
    }

    /**
     * @notice Check if the user has rKSU.
     * @param user The address of the user.
     * @return True if the user has any rKSU.
     */
    function hasUserRKSU(address user) public view returns (bool) {
        return _ksuLocking.balanceOf(user) > 0;
    }

    /**
     * @notice Check if the user can deposit in the junior tranche.
     * @dev If the system variable is set to true, the user can only deposit in the junior tranche if he has any rKSU balance.
     * If the system variable is set to false, the user can always deposit in the junior tranche.
     * @param user The address of the user.
     * @return True if the user can deposit in the junior tranche.
     */
    function canUserDepositInJuniorTranche(address user) external view returns (bool) {
        if (_systemVariables.userCanOnlyDepositToJuniorTrancheWhenHeHasRKSU()) {
            return hasUserRKSU(user);
        } else {
            return true;
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

    /**
     * @notice Calculate the user loyalty level for the current epoch.
     * @param user The address of the user.
     * @return currentEpoch The current epoch number.
     * @return loyaltyLevel The user's loyalty level.
     */
    function userLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint8 loyaltyLevel) {
        LoyaltyGlobalParameters memory params = _loyaltyParameters();
        currentEpoch = params.currentEpoch;
        (loyaltyLevel,,) = _userLoyaltyLevel(user, params);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Batch calculate user loyalty levels for the current epoch.
     * @dev This function is used to calculate user loyalty levels in batches.
     * The function will calculate the loyalty level for the user and update the user's loyalty level for the current epoch.
     * Can only be called during the clearing time.
     * @param batchSize The size of the batch.
     */
    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external {
        if (!_systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (batchSize == 0) {
            return;
        }

        LoyaltyGlobalParameters memory params = _loyaltyParameters();

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
            _userLoyaltyRewards.emitUserLoyaltyReward(user, params.currentEpoch, loyaltyLevel, activeDepositAmount);

            emit UserLoyaltyLevelUpdated(user, params.currentEpoch, loyaltyLevel);
        }

        _epochUserLoyaltyProcessing[params.currentEpoch].processedUsersCount = endUser;

        if (_epochUserLoyaltyProcessing[params.currentEpoch].userCount == endUser) {
            emit UserLoyaltyLevelsForEpochProcessed(params.currentEpoch, endUser);
        }
    }

    /**
     * @notice Notices the user manager contract of a user requesting a deposit.
     * @dev This function is used to add user to the all users array and user lending pools array.
     * Can only be called by the lending pool manager.
     * @param user The address of the user.
     * @param lendingPool The address of the lending pool.
     */
    function userRequestedDeposit(address user, address lendingPool) external {
        if (msg.sender != _lendingPoolManager) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }

        // add user to all users if it is not already added
        if (!_isUser[user]) {
            _allUsers.push(user);
            _isUser[user] = true;
        }

        // add lending pools to user lending pools array if it is not already added
        if (!_isUserPartOfLendingPool[lendingPool][user]) {
            _userLendingPools[user].push(lendingPool);
            _isUserPartOfLendingPool[lendingPool][user] = true;
        }
    }

    /**
     * @notice Increase the user active tranche count.
     * @dev This function is called by the tranche when a user first deposit is accepted in the tranche.
     * If the user has no active tranches before, the user fees are enabled.
     * @param user The address of the user that deposited in the tranche.
     * @param lendingPool The address of the lending pool corresponding to the tranche.
     */
    function addUserActiveTranche(address user, address lendingPool) external verifyTranche(lendingPool, msg.sender) {
        _userActiveTrancheCount[user]++;

        if (_userActiveTrancheCount[user] == 1) {
            _ksuLocking.enableFeesForUser(user);
        }
    }

    /**
     * @notice Decrease the user active tranche count.
     * @dev This function is called by the tranche when a user redeems all of his shares from the tranche.
     * If the user has no active tranches after, the user fees are disabled.
     * @param user The address of the user that redeemed all of his shares from the tranche.
     * @param lendingPool The address of the lending pool corresponding to the tranche.
     */
    function removeUserActiveTranche(address user, address lendingPool)
        external
        verifyTranche(lendingPool, msg.sender)
    {
        _userActiveTrancheCount[user]--;

        if (_userActiveTrancheCount[user] == 0) {
            _ksuLocking.disableFeesForUser(user);
        }
    }

    /**
     * @notice Update users and user lending pools arrays. Removes user from all users if it has no balance in lending pools left.
     * @dev This function is used to remove users and its lending pools and from arrays if balance is 0.
     * Processing of users and user lending pools is done in reverse order. From `toIndex` to `fromIndex`.
     * `fromIndex` is strictly less or equal to `toIndex`.
     * @param fromIndex The starting index to process of the all users array.
     * @param toIndex The ending index to process of the all users array. Including the desired processed index.
     */
    function updateUserLendingPools(uint256 fromIndex, uint256 toIndex) external {
        if (_systemVariables.isClearingTime()) {
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
        uint256 nextEpoch = _systemVariables.currentEpochNumber() + 1;

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

                (uint256 activeDepositAmount, uint256 pendingDepositAmount) = _userLendingPoolActiveAndPendingBalance(
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

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _loyaltyParameters() private view returns (LoyaltyGlobalParameters memory params) {
        params.currentEpoch = _systemVariables.currentEpochNumber();
        params.ksuPrice = _systemVariables.ksuEpochTokenPrice();
        params.loyaltyThresholds = _systemVariables.loyaltyThresholds();
    }

    function _userLoyaltyLevel(address user, LoyaltyGlobalParameters memory params)
        private
        view
        returns (uint8 loyaltyLevel, uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        // get user deposit amount for the current epoch
        (activeDepositAmount, pendingDepositAmount) =
            _userTotalPendingAndActiveDepositedAmount(user, params.currentEpoch);
        uint256 userDepositAmount = activeDepositAmount + pendingDepositAmount;

        // get user rKSU balance
        uint256 userRKSU = _ksuLocking.balanceOf(user);

        // calculate rKSU in asset (USDC)
        uint256 rKSUInUSDC = _rKSUInUSDC(userRKSU, params.ksuPrice);

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

    function _userTotalPendingAndActiveDepositedAmount(address user, uint256 epochId)
        private
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        // loop through all user lending pools
        for (uint256 i; i < _userLendingPools[user].length; ++i) {
            (uint256 poolActiveDepositAmount, uint256 poolPendingDepositAmount) =
                _userLendingPoolActiveAndPendingBalance(user, _userLendingPools[user][i], epochId);

            activeDepositAmount += poolActiveDepositAmount;
            pendingDepositAmount += poolPendingDepositAmount;
        }
    }

    function _userLendingPoolActiveAndPendingBalance(address user, address lendingPool, uint256 epochId)
        private
        view
        returns (uint256 activeDepositAmount, uint256 pendingDepositAmount)
    {
        activeDepositAmount = ILendingPool(lendingPool).userBalance(user);

        // get user pending deposit amount
        IPendingPool pendingPool = IPendingPool(ILendingPool(lendingPool).pendingPool());
        pendingDepositAmount = pendingPool.userPendingDepositAmount(user, epochId);
    }

    function _rKSUInUSDC(uint256 rKSUAmount, uint256 ksuPrice) internal pure returns (uint256 rKSUInUSDC) {
        // NOTE: 1e12 is the difference in decimal places between rKSU and USDC
        rKSUInUSDC = rKSUAmount * ksuPrice / KSU_PRICE_MULTIPLIER / 1e12;
    }

    function _removeLendingPoolFromUser(address user, uint256 userLendingPoolIndex) internal {
        _userLendingPools[user][userLendingPoolIndex] = _userLendingPools[user][_userLendingPools[user].length - 1];
        _userLendingPools[user].pop();
    }

    function _removeUserFromAllUsers(uint256 userIndex) internal {
        _isUser[_allUsers[userIndex]] = false;
        _allUsers[userIndex] = _allUsers[_allUsers.length - 1];
        _allUsers.pop();
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Manually updates user active tranche count.
     * @dev SHOULD ONLY BE CALLED TO MANUALLY SYNC USER ACTIVE TRANCHE COUNT AFTER UPGRADING THE CONTRACT.
     * @param users The array of users.
     * @param counts The array of user active tranche counts.
     */
    function _batchSetUserActiveTrancheCount(address[] calldata users, uint256[] calldata counts) private {
        if (users.length != counts.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < users.length; ++i) {
            if (_userActiveTrancheCount[users[i]] == 0 && counts[i] > 0) {
                _ksuLocking.enableFeesForUser(users[i]);
            } else if (_userActiveTrancheCount[users[i]] > 0 && counts[i] == 0) {
                _ksuLocking.disableFeesForUser(users[i]);
            }

            _userActiveTrancheCount[users[i]] = counts[i];
        }
    }

    /* ========== MODIFIERS ========== */

    modifier verifyTranche(address lendingPool, address tranche) {
        if (
            !ILendingPoolManager(_lendingPoolManager).isLendingPool(lendingPool)
                || !ILendingPool(lendingPool).isLendingPoolTranche(tranche)
        ) {
            revert ILendingPoolErrors.InvalidTranche(lendingPool, tranche);
        }
        _;
    }
}
