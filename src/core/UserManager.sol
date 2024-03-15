// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IUserManager.sol";
import "./interfaces/ISystemVariables.sol";
import "./interfaces/lendingPool/ILendingPool.sol";
import "./interfaces/lendingPool/IPendingPool.sol";
import "../locking/interfaces/IKSULocking.sol";
import "../shared/CommonErrors.sol";
import "./Constants.sol";

struct LoyaltyGlobalParameters {
    uint256 currentEpoch;
    uint256 ksuPrice;
    uint256[] loyaltyThresholds;
}

contract UserManager is IUserManager {
    ISystemVariables public immutable systemVariables;
    IKSULocking public immutable ksuLocking;

    address[] public allUsers;
    mapping(address => bool) public isUser;

    mapping(address user => address[] lendingPools) private _userLendingPools;
    mapping(address lendingPool => mapping(address user => bool)) public isUserPartOfLendingPool;

    mapping(address user => mapping(uint256 epochId => uint256 loyaltyLevel)) public _userEpochLoyaltyLevel;

    mapping(uint256 epochId => EpochUserLoyaltyProcessing) private _epochUserLoyaltyProcessing;

    constructor(ISystemVariables systemVariables_, IKSULocking ksuLocking_) {
        systemVariables = systemVariables_;
        ksuLocking = ksuLocking_;
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

            uint256 loyaltyLevel = _getUserLoyaltyLevel(user, params);

            // update user loyalty level
            _userEpochLoyaltyLevel[user][params.currentEpoch] = loyaltyLevel;

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
        loyaltyLevel = _getUserLoyaltyLevel(user, params);
    }

    function _getUserLoyaltyLevel(address user, LoyaltyGlobalParameters memory params)
        private
        view
        returns (uint256 loyaltyLevel)
    {
        uint256 userDepositAmount;

        // loop through all user lending pools
        for (uint256 i; i < _userLendingPools[user].length; ++i) {
            // get the user's available lending pool balance
            ILendingPool lendingPool = ILendingPool(_userLendingPools[user][i]);
            uint256 userLendingPoolBalance = lendingPool.getUserBalance(user);

            // get user pending deposit amount
            // get user pending withdrawal amount
            IPendingPool pendingPool = IPendingPool(lendingPool.getPendingPool());

            uint256 pendingDepositAmount = pendingPool.getUserPendingDepositAmount(user, params.currentEpoch);

            // sum up
            userDepositAmount += userLendingPoolBalance + pendingDepositAmount;
        }

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

    function _getRKSUInUSDC(uint256 rKSUAmount, uint256 ksuPrice) internal pure returns (uint256 rKSUInUSDC) {
        // NOTE: 1e12 is the difference in decimal places between rKSU and USDC
        rKSUInUSDC = rKSUAmount * ksuPrice / KSU_PRICE_MULTIPLIER / 1e12;
    }

    // TODO: add access control
    function userRequestedDeposit(address user, address lendingPool) external {
        if (!isUser[user]) {
            allUsers.push(user);
            isUser[user] = true;
        }

        if (!isUserPartOfLendingPool[lendingPool][user]) {
            _userLendingPools[user].push(lendingPool);
            isUserPartOfLendingPool[lendingPool][user] = true;
        }
    }

    function _removeLendingPoolFromUser(address user, address lendingPool) internal {
        // TODO: not during clearing period
        for (uint256 i; i < _userLendingPools[user].length; ++i) {
            if (_userLendingPools[user][i] == lendingPool) {
                _userLendingPools[user][i] = _userLendingPools[user][_userLendingPools[user].length - 1];
                _userLendingPools[user].pop();
                break;
            }
        }

        isUserPartOfLendingPool[lendingPool][user] = false;
    }
}
