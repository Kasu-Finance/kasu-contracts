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
    ISystemVariables internal immutable _systemVariables;

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

    /// @dev Retired: the former bare active tranche counter, which a double removal could desync.
    /// Kept only to hold its storage slot. Replaced by `_isUserActiveInTranche` and `_activeTrancheCount`.
    /// @custom:oz-renamed-from _userActiveTrancheCount
    mapping(address user => uint256) private __deprecatedUserActiveTrancheCount;

    /// @notice Whether the user holds active shares in the tranche, as reported by the tranche.
    mapping(address user => mapping(address tranche => bool)) private _isUserActiveInTranche;

    /// @notice Number of tranches the user is active in. Always equals the number of set flags above.
    mapping(address user => uint256) private _activeTrancheCount;

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

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Number of tranches the user holds active shares in.
     * @param user The address of the user.
     * @return The active tranche count.
     */
    function userActiveTrancheCount(address user) external view returns (uint256) {
        return _activeTrancheCount[user];
    }

    /**
     * @notice Whether the user is recorded as active in the tranche.
     * @param user The address of the user.
     * @param tranche The tranche address.
     * @return True if the user is recorded as active in the tranche.
     */
    function isUserActiveInTranche(address user, address tranche) external view returns (bool) {
        return _isUserActiveInTranche[user][tranche];
    }

    /**
     * @notice Get the calculated user epoch loyalty level.
     * @dev If the loyalty level is not calculated for the epoch it will return 0.
     * @param user The address of the user.
     * @param epoch The epoch number.
     * @return The calculated user's loyalty level for the epoch.
     */
    function calculatedUserEpochLoyaltyLevel(address user, uint256 epoch) external view virtual returns (uint8) {
        return _userEpochLoyaltyLevel[user][epoch];
    }

    /**
     * @notice Get the epoch user loyalty processing details.
     * @param epoch The epoch number.
     * @return The epoch user loyalty processing details.
     */
    function epochUserLoyaltyProcessing(uint256 epoch)
        external
        view
        virtual
        returns (EpochUserLoyaltyProcessing memory)
    {
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
    function canUserDepositInJuniorTranche(address user) external view virtual returns (bool) {
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
    function areUserEpochLoyaltyLevelProcessed(uint256 epoch) external view virtual returns (bool) {
        return _epochUserLoyaltyProcessing[epoch].didStart
            && _epochUserLoyaltyProcessing[epoch].processedUsersCount == _epochUserLoyaltyProcessing[epoch].userCount;
    }

    /**
     * @notice Calculate the user loyalty level for the current epoch.
     * @param user The address of the user.
     * @return currentEpoch The current epoch number.
     * @return loyaltyLevel The user's loyalty level.
     */
    function userLoyaltyLevel(address user) external view virtual returns (uint256 currentEpoch, uint8 loyaltyLevel) {
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
    function batchCalculateUserLoyaltyLevels(uint256 batchSize) external virtual {
        if (!_systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }

        if (batchSize == 0) {
            return;
        }

        // M-04 Layer 2: self-heal the KSU epoch price if the cron missed updating it this epoch.
        // Idempotent — no-op when the snapshot is already fresh for the current epoch.
        _systemVariables.updateKsuEpochTokenPrice();

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
     * @notice Marks the user active in the calling tranche.
     * @dev Called by the tranche whenever the user ends an interaction holding shares in it. Idempotent per
     * (user, tranche), so a repeated call changes nothing and a missed record heals on the next interaction.
     * If the user had no active tranches before, the user fees are enabled.
     * @param user The address of the user holding shares in the tranche.
     * @param lendingPool The address of the lending pool corresponding to the tranche.
     */
    function addUserActiveTranche(address user, address lendingPool) external verifyTranche(lendingPool, msg.sender) {
        _setUserActiveInTranche(user, lendingPool, msg.sender, true);
    }

    /**
     * @notice Marks the user inactive in the calling tranche.
     * @dev Called by the tranche when the user's last shares in it are redeemed. Idempotent per (user, tranche).
     * A removal for a pair not recorded as active is skipped and surfaced with `RemovalForInactiveTranche`; it can
     * never revert a clearing. If the user has no active tranches after, the user fees are disabled.
     * @param user The address of the user that redeemed all of his shares from the tranche.
     * @param lendingPool The address of the lending pool corresponding to the tranche.
     */
    function removeUserActiveTranche(address user, address lendingPool)
        external
        verifyTranche(lendingPool, msg.sender)
    {
        if (!_setUserActiveInTranche(user, lendingPool, msg.sender, false)) {
            emit RemovalForInactiveTranche(user, lendingPool, msg.sender);
        }
    }

    /**
     * @notice Sets the user's record for the calling tranche to the state the tranche reports.
     * @dev Used by `LendingPoolTranche.syncTrancheUser`, which passes `userActiveShares > 0` directly, so the
     * repair needs no call back into the tranche. Idempotent; emits nothing when the record already matches.
     * @param user The address of the user.
     * @param lendingPool The address of the lending pool corresponding to the tranche.
     * @param isActive Whether the user holds active shares in the tranche.
     */
    function syncUserActiveTrancheFromTranche(address user, address lendingPool, bool isActive)
        external
        verifyTranche(lendingPool, msg.sender)
    {
        _setUserActiveInTranche(user, lendingPool, msg.sender, isActive);
    }

    /**
     * @notice Re-derives the user's record for a tranche from the tranche's active shares.
     * @dev Permissionless and idempotent: the result only depends on `userActiveShares` on-chain, so any caller
     * can only move the record towards the truth. Repairs any desync without an admin.
     * @param user The address of the user.
     * @param lendingPool The lending pool of the tranche.
     * @param tranche The tranche address.
     */
    function syncUserActiveTranche(address user, address lendingPool, address tranche)
        external
        verifyTranche(lendingPool, tranche)
    {
        _setUserActiveInTranche(user, lendingPool, tranche, ILendingPoolTranche(tranche).userActiveShares(user) > 0);
    }

    /**
     * @notice Aligns the user's KSU fee eligibility with the user's active tranche count.
     * @dev Permissionless and idempotent. Fees are enabled while a user is active in at least one tranche and
     * disabled otherwise, the same rule the count transitions apply. Repairs users whose fees were left enabled
     * by the retired counter after they had left every tranche (or the reverse).
     * @param user The address of the user.
     */
    function syncUserFees(address user) external {
        bool shouldBeEnabled = _activeTrancheCount[user] > 0;
        if (_ksuLocking.isFeeRecipientEnabled(user) == shouldBeEnabled) return;

        if (shouldBeEnabled) {
            _ksuLocking.enableFeesForUser(user);
        } else {
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
        // M-04 Layer 3: view-safe fallback to spot price if the snapshot is stale. In the mutative
        // clearing path the preceding updateKsuEpochTokenPrice() call guarantees a fresh snapshot,
        // so this returns ksuEpochTokenPrice directly. In view-only callers (userLoyaltyLevel) it
        // prevents a stale snapshot from corrupting external reads.
        params.ksuPrice = _systemVariables.ksuEpochTokenPriceFresh();
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
        _isUserPartOfLendingPool[_userLendingPools[user][userLendingPoolIndex]][user] = false;
        _userLendingPools[user][userLendingPoolIndex] = _userLendingPools[user][_userLendingPools[user].length - 1];
        _userLendingPools[user].pop();
    }

    function _removeUserFromAllUsers(uint256 userIndex) internal {
        _isUser[_allUsers[userIndex]] = false;
        _allUsers[userIndex] = _allUsers[_allUsers.length - 1];
        _allUsers.pop();
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /// @dev The one place a (user, tranche) record changes. Returns false when it already matched.
    function _setUserActiveInTranche(address user, address lendingPool, address tranche, bool isActive)
        private
        returns (bool changed)
    {
        if (_isUserActiveInTranche[user][tranche] == isActive) return false;

        _isUserActiveInTranche[user][tranche] = isActive;
        uint256 count = _activeTrancheCount[user];

        if (isActive) {
            _activeTrancheCount[user] = ++count;
            if (count == 1) {
                _ksuLocking.enableFeesForUser(user);
            }
        } else {
            _activeTrancheCount[user] = --count;
            if (count == 0) {
                _ksuLocking.disableFeesForUser(user);
            }
        }

        emit UserActiveTrancheUpdated(user, lendingPool, tranche, isActive, count);
        return true;
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
