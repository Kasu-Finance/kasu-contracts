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

struct LoyaltyGlobalParameters {
    uint256 currentEpoch;
    uint256 ksuPrice;
    uint256[] loyaltyThresholds;
}

contract UserManager is IUserManager, Initializable {
    ISystemVariables public immutable systemVariables;
    IKSULocking public immutable ksuLocking;
    IUserLoyaltyRewards public immutable userLoyaltyRewards;
    address public lendingPoolManager;

    address[] public allUsers;
    mapping(address => bool) public isUser;

    mapping(address user => address[] lendingPools) private _userLendingPools;
    mapping(address lendingPool => mapping(address user => bool)) public isUserPartOfLendingPool;

    mapping(address user => mapping(uint256 epochId => uint256 loyaltyLevel)) public _userEpochLoyaltyLevel;

    mapping(uint256 epochId => EpochUserLoyaltyProcessing) private _epochUserLoyaltyProcessing;

    constructor(ISystemVariables systemVariables_, IKSULocking ksuLocking_, IUserLoyaltyRewards userLoyaltyRewards_) {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(address(ksuLocking_));
        AddressLib.checkIfZero(address(userLoyaltyRewards_));

        systemVariables = systemVariables_;
        ksuLocking = ksuLocking_;
        userLoyaltyRewards = userLoyaltyRewards_;

        _disableInitializers();
    }

    function initialize(address lendingPoolManager_) external initializer {
        AddressLib.checkIfZero(lendingPoolManager_);
        lendingPoolManager = lendingPoolManager_;
    }

    function getCalculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view returns (uint256) {
        return _userEpochLoyaltyLevel[user][epoch];
    }

    function getEpochUserLoyaltyProcessing(uint256 epoch) external view returns (EpochUserLoyaltyProcessing memory) {
        return _epochUserLoyaltyProcessing[epoch];
    }

    function getUserLendingPools(address user) external view returns (address[] memory lendingPools) {
        return _userLendingPools[user];
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    /**
     * @notice Get the total pending and active deposited amount.
     * @dev Returns the amount including pending deposits for the next epoch.
     * @param user The address of the user.
     * @return The total deposited amount for the user.
     */
    function getUserTotalPendingAndActiveDepositedAmount(address user) external view returns (uint256) {
        uint256 nextEpoch = systemVariables.getCurrentEpochNumber() + 1;

        (uint256 activeDepositAmount, uint256 pendingDepositAmount) =
            _getUserTotalPendingAndActiveDepositedAmount(user, nextEpoch);

        return activeDepositAmount + pendingDepositAmount;
    }

    /**
     * @notice Get the total pending and active deposited amount for the user for the current epoch.
     * @dev Only returns the amount that will be used to calculate the user's loyalty level this clearing period.
     * @param user The address of the user.
     * @return The total deposited amount for the user for the current epoch.
     */
    function getUserTotalPendingAndActiveDepositedAmountForCurrentEpoch(address user) external view returns (uint256) {
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();

        (uint256 activeDepositAmount, uint256 pendingDepositAmount) =
            _getUserTotalPendingAndActiveDepositedAmount(user, currentEpoch);

        return activeDepositAmount + pendingDepositAmount;
    }

    function hasUserRKSU(address user) public view returns (bool) {
        return ksuLocking.balanceOf(user) > 0;
    }

    function canUserDepositInJuniorTranche(address user) external view returns (bool) {
        if (!systemVariables.getUserCanDepositToJuniorTrancheWhenHeHasRKSU()) {
            return true;
        } else {
            return hasUserRKSU(user);
        }
    }

    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external {
        if (!systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (batchSize == 0) {
            return;
        }

        LoyaltyGlobalParameters memory params = _getLoyaltyParameters();

        if (!_epochUserLoyaltyProcessing[params.currentEpoch].didStart) {
            _epochUserLoyaltyProcessing[params.currentEpoch].userCount = allUsers.length;
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
            address user = allUsers[i];

            (uint256 loyaltyLevel, uint256 activeDepositAmount,) = _getUserLoyaltyLevel(user, params);

            // update user loyalty level
            _userEpochLoyaltyLevel[user][params.currentEpoch] = loyaltyLevel;

            userLoyaltyRewards.emitUserLoyaltyReward(user, params.currentEpoch, loyaltyLevel, activeDepositAmount);

            emit UserLoyaltyLevelUpdated(user, params.currentEpoch, loyaltyLevel);
        }

        _epochUserLoyaltyProcessing[params.currentEpoch].processedUsersCount = endUser;

        if (_epochUserLoyaltyProcessing[params.currentEpoch].userCount == endUser) {
            emit UserLoyaltyLevelsForEpochProcessed(params.currentEpoch, endUser);
        }
    }

    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view returns (bool) {
        return _epochUserLoyaltyProcessing[epoch].didStart
            && _epochUserLoyaltyProcessing[epoch].processedUsersCount == _epochUserLoyaltyProcessing[epoch].userCount;
    }

    function _getLoyaltyParameters() private view returns (LoyaltyGlobalParameters memory params) {
        params.currentEpoch = systemVariables.getCurrentEpochNumber();
        params.ksuPrice = systemVariables.ksuEpochTokenPrice();
        params.loyaltyThresholds = systemVariables.loyaltyThresholds();
    }

    function getUserLoyaltyLevel(address user) external view returns (uint256 currentEpoch, uint256 loyaltyLevel) {
        LoyaltyGlobalParameters memory params = _getLoyaltyParameters();
        currentEpoch = params.currentEpoch;
        (loyaltyLevel,,) = _getUserLoyaltyLevel(user, params);
    }

    function _getUserLoyaltyLevel(address user, LoyaltyGlobalParameters memory params)
        private
        view
        returns (uint256 loyaltyLevel, uint256 activeDepositAmount, uint256 pendingDepositAmount)
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
        activeDepositAmount = ILendingPool(lendingPool).getUserBalance(user);

        // get user pending deposit amount
        IPendingPool pendingPool = IPendingPool(ILendingPool(lendingPool).getPendingPool());
        pendingDepositAmount = pendingPool.getUserPendingDepositAmount(user, epochId);
    }

    function _getRKSUInUSDC(uint256 rKSUAmount, uint256 ksuPrice) internal pure returns (uint256 rKSUInUSDC) {
        // NOTE: 1e12 is the difference in decimal places between rKSU and USDC
        rKSUInUSDC = rKSUAmount * ksuPrice / KSU_PRICE_MULTIPLIER / 1e12;
    }

    function userRequestedDeposit(address user, address lendingPool) external {
        if (msg.sender != lendingPoolManager) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }

        if (!isUser[user]) {
            allUsers.push(user);
            isUser[user] = true;
        }

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

        if (allUsers.length == 0) {
            return;
        }

        if (toIndex >= allUsers.length) {
            unchecked {
                toIndex = allUsers.length - 1;
            }
        }

        if (toIndex < fromIndex) {
            revert BadUserIndex();
        }

        uint256 nextEpoch = systemVariables.getCurrentEpochNumber() + 1;

        while (fromIndex <= toIndex) {
            address user = allUsers[toIndex];
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
        isUser[allUsers[userIndex]] = false;
        allUsers[userIndex] = allUsers[allUsers.length - 1];
        allUsers.pop();
    }
}
