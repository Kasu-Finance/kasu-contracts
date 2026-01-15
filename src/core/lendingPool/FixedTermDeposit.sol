// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/IFixedTermDeposit.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../interfaces/ISystemVariables.sol";
import {TaskStatus} from "../interfaces/clearing/IClearingStepsData.sol";
import "../../shared/AddressLib.sol";
import "../../shared/CommonErrors.sol";

/**
 * @notice Struct to track fixed term deposit clearing per epoch.
 * @custom:member nextIndexToProcess Index of the next fixed term deposit to process for the lending pool.
 * @custom:member status Status of the fixed term deposit clearing for the lending pool.
 */
struct FixedTermDepositsEpoch {
    uint256 nextIndexToProcess;
    TaskStatus status;
}

/**
 * @title FixedTermDeposit contract.
 * @notice Contract to set and lock users' lending pool tranche fixed term deposits.
 * @dev Fixed term deposits are locked for a specific duration in return for a fixed interest rate.
 * Users can request to withdraw their fixed term deposits before the lock duration ends.
 * If the user requests a withdrawal, the withdrawal is triggered during the clearing process with the highest priority.
 * If the user does not request a withdrawal, the fixed term deposit is unlocked after the lock duration ends and tranche tokens are returned to the user.
 * The clearing process calculates the interest rate difference and mints or burns tranche shares accordingly.
 */
contract FixedTermDeposit is Initializable, IFixedTermDeposit {
    /// @notice System variables contract.
    ISystemVariables private immutable _systemVariables;

    /// @notice Lending pool manager contract.
    ILendingPoolManager private _lendingPoolManager;

    /// @notice Clearing coordinator contract.
    IClearingCoordinator private _clearingCoordinator;

    /// @dev Lending pool fixed term deposit configurations.
    mapping(address lendingPool => mapping(uint256 configId => FixedTermDepositConfig)) private
        _lendingPoolFixedTermDepositConfigurations;

    /// @dev Count of fixed term deposit configurations for a lending pool.
    mapping(address lendingPool => uint256 configCount) public lendingPoolFixedTermDepositConfigCount;

    /// @dev Withdrawal configuration for a lending pool.
    mapping(address lendingPool => LendingPoolWithdrawalConfiguration) private _lendingPoolWithdrawalConfiguration;

    /// @dev Ids of active locked fixed term deposits for a lending pool.
    mapping(address lendingPool => uint256[] fixedTermDepositIds) private _lendingPoolFixedTermDepositIds;

    /// @dev Id to fixed term deposit lock mapping.
    mapping(address lendingPool => mapping(uint256 id => UserLendingPoolFixedTermDeposit)) private
        _lendingPoolFixedTermDepositIdToLock;

    /// @dev Next fixed term deposit id for a lending pool.
    mapping(address lendingPool => uint256 nextId) private _lendingPoolFixedTermDepositNextId;

    /// @dev Allowlist of users for fixed term deposit configuration for a lending pool.
    mapping(address lendingPool => mapping(uint256 configId => mapping(address user => bool isAllowed))) public
        fixedTermDepositsAllowlist;

    /// @dev Clearing data for lending pool fixed term deposits per epoch.
    mapping(address lendingPool => mapping(uint256 epoch => FixedTermDepositsEpoch)) private
        _fixedTermDepositsClearingPerEpoch;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param systemVariables_ System variables contract address.
     */
    constructor(ISystemVariables systemVariables_) {
        AddressLib.checkIfZero(address(systemVariables_));
        _systemVariables = systemVariables_;

        _disableInitializers();
    }

    /**
     * @notice Initializes the fixed term deposit contract.
     * @param lendingPoolManager_ Lending pool manager address.
     * @param clearingCoordinator_ Clearing coordinator address.
     */
    function initialize(ILendingPoolManager lendingPoolManager_, IClearingCoordinator clearingCoordinator_)
        external
        initializer
    {
        AddressLib.checkIfZero(address(lendingPoolManager_));
        AddressLib.checkIfZero(address(clearingCoordinator_));
        _lendingPoolManager = lendingPoolManager_;
        _clearingCoordinator = clearingCoordinator_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Status of the lending pool fixed term deposit clearing for an epoch.
     * @param lendingPool Lending pool address.
     * @param epoch Epoch number.
     * @return TaskStatus Status of the fixed term deposit clearing for the lending pool.
     */
    function fixedTermDepositsClearingPerEpochStatus(address lendingPool, uint256 epoch)
        external
        view
        returns (TaskStatus)
    {
        return _fixedTermDepositsClearingPerEpoch[lendingPool][epoch].status;
    }

    /**
     * @notice Lending pool fixed term deposit details.
     * @param lendingPool Lending pool address.
     * @param fixedTermDepositId Id of the fixed term deposit.
     * @return Lending pool fixed term deposit details of the id.
     */
    function lendingPoolFixedTermDeposit(address lendingPool, uint256 fixedTermDepositId)
        external
        view
        returns (UserLendingPoolFixedTermDeposit memory)
    {
        return _lendingPoolFixedTermDeposit(lendingPool, fixedTermDepositId);
    }

    /**
     * @notice Count of fixed term deposit configurations for a lending pool.
     * @param lendingPool Lending pool address.
     * @return Count of fixed term deposit configurations for a lending pool..
     */
    function lendingPoolFixedTermDepositsCount(address lendingPool) external view returns (uint256) {
        return _lendingPoolFixedTermDepositIds[lendingPool].length;
    }

    /**
     * @notice List of active locked fixed term deposit ids for a lending pool.
     * @param lendingPool Lending pool address.
     * @return List of active locked fixed term deposit ids for a lending pool.
     */
    function lendingPoolFixedTermDepositIds(address lendingPool) external view returns (uint256[] memory) {
        return _lendingPoolFixedTermDepositIds[lendingPool];
    }

    /**
     * @notice Tranche address for a fixed term deposit configuration.
     * @param lendingPool Lending pool address.
     * @param configId Id of the fixed term deposit configuration.
     * @return tranche Tranche address.
     */
    function configIdTranche(address lendingPool, uint256 configId) external view returns (address tranche) {
        return _lendingPoolFixedTermDepositConfigurations[lendingPool][configId].tranche;
    }

    /**
     * @notice Fixed term deposit configuration for a lending pool.
     * @param lendingPool Lending pool address.
     * @param configId Id of the fixed term deposit configuration.
     * @return Fixed term deposit configuration.
     */
    function lendingPoolFixedTermConfig(address lendingPool, uint256 configId)
        external
        view
        returns (FixedTermDepositConfig memory)
    {
        return _lendingPoolFixedTermDepositConfigurations[lendingPool][configId];
    }

    /**
     * @notice Withdrawal configuration details for the lending pool.
     * @dev Number of epochs in advance to request a withdrawal and cancel a withdrawal request.
     * @param lendingPool Lending pool address.
     * @return Withdrawal configuration details.
     */
    function lendingPoolWithdrawalConfiguration(address lendingPool)
        external
        view
        returns (LendingPoolWithdrawalConfiguration memory)
    {
        return _lendingPoolWithdrawalConfiguration[lendingPool];
    }

    /**
     * @notice Verify the fixed term deposit parameters.
     * @dev Revert if the parameters are invalid.
     * @param user User address.
     * @param lendingPool Lending pool address.
     * @param tranche Tranche address.
     * @param configId Id of the fixed term deposit configuration.
     */
    function verifyFixedTermDepositParameters(address user, address lendingPool, address tranche, uint256 configId)
        public
        view
    {
        _verifyConfigId(lendingPool, configId);

        FixedTermDepositConfig storage fixedTermDepositConfig =
            _lendingPoolFixedTermDepositConfigurations[lendingPool][configId];

        if (fixedTermDepositConfig.fixedTermDepositStatus == FixedTermDepositStatus.WHITELISTED_ONLY) {
            if (!fixedTermDepositsAllowlist[lendingPool][configId][user]) {
                revert UserNotWhitelistedForFixedTermDeposit(lendingPool, configId, user);
            }
        } else if (fixedTermDepositConfig.fixedTermDepositStatus == FixedTermDepositStatus.DISABLED) {
            revert FixedTermDepositDisabled(lendingPool, configId);
        }

        if (fixedTermDepositConfig.tranche != tranche) {
            revert InvalidTrancheForFixedTermDeposit(lendingPool, configId, fixedTermDepositConfig.tranche, tranche);
        }
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Add a fixed term deposit configuration to a lending pool.
     * @param lendingPool Lending pool address.
     * @param tranche Tranche address.
     * @param epochLockDuration Duration of the lock in epochs.
     * @param epochInterestRate Interest rate for the lock.
     * @param whitelistedOnly Flag to allow only whitelisted users to lock. If false everyone can lock.
     * @return fixedTermConfigId Fixed term deposit configuration id.
     */
    function addLendingPoolTrancheFixedTermDeposit(
        address lendingPool,
        address tranche,
        uint256 epochLockDuration,
        uint256 epochInterestRate,
        bool whitelistedOnly
    ) external onlyLendingPoolManager verifyTranche(lendingPool, tranche) returns (uint256 fixedTermConfigId) {
        _verifyTrancheInterestRate(epochInterestRate);

        if (epochLockDuration == 0) {
            revert InvalidConfiguration();
        }

        FixedTermDepositStatus fixedTermDepositStatus =
            whitelistedOnly ? FixedTermDepositStatus.WHITELISTED_ONLY : FixedTermDepositStatus.EVERYONE;

        lendingPoolFixedTermDepositConfigCount[lendingPool]++;
        fixedTermConfigId = lendingPoolFixedTermDepositConfigCount[lendingPool];

        _lendingPoolFixedTermDepositConfigurations[lendingPool][fixedTermConfigId] = FixedTermDepositConfig({
            tranche: tranche,
            epochInterestRate: SafeCast.toUint64(epochInterestRate),
            epochLockDuration: SafeCast.toUint16(epochLockDuration),
            fixedTermDepositStatus: fixedTermDepositStatus
        });

        emit LendingPoolTrancheFixedTermDepositConfigAdded(
            lendingPool, tranche, fixedTermConfigId, epochLockDuration, epochInterestRate, fixedTermDepositStatus
        );
    }

    /**
     * @notice Update the fixed term deposit status for a lending pool.
     * @param lendingPool Lending pool address.
     * @param fixedTermConfigId Id of the fixed term deposit configuration.
     * @param fixedTermDepositStatus New status of the fixed term deposit.
     */
    function updateLendingPoolTrancheFixedInterestStatus(
        address lendingPool,
        uint256 fixedTermConfigId,
        FixedTermDepositStatus fixedTermDepositStatus
    ) external onlyLendingPoolManager {
        _verifyConfigId(lendingPool, fixedTermConfigId);

        FixedTermDepositConfig storage fixedTermDepositConfig =
            _lendingPoolFixedTermDepositConfigurations[lendingPool][fixedTermConfigId];

        if (fixedTermDepositConfig.fixedTermDepositStatus != fixedTermDepositStatus) {
            fixedTermDepositConfig.fixedTermDepositStatus = fixedTermDepositStatus;

            emit LendingPoolTrancheFixedTermDepositConfigStatusUpdated(
                lendingPool, fixedTermConfigId, fixedTermDepositStatus
            );
        }
    }

    /**
     * @notice Update the withdrawal configuration for a lending pool.
     * @param lendingPool Lending pool address.
     * @param withdrawalConfiguration Withdrawal configuration details.
     */
    function updateLendingPoolWithdrawalConfiguration(
        address lendingPool,
        LendingPoolWithdrawalConfiguration calldata withdrawalConfiguration
    ) external onlyLendingPoolManager {
        if (withdrawalConfiguration.cancelRequestEpochsInAdvance > withdrawalConfiguration.requestEpochsInAdvance) {
            revert InvalidConfiguration();
        }

        _lendingPoolWithdrawalConfiguration[lendingPool] = withdrawalConfiguration;

        emit LendingPoolWithdrawalConfigurationUpdated(lendingPool, withdrawalConfiguration);
    }

    /**
     * @notice Update the fixed term deposit allowlist for a lending pool.
     * @dev This is only applicable for fixed term deposits with status WHITELISTED_ONLY.
     * @param lendingPool Lending pool address.
     * @param configId Id of the fixed term deposit configuration.
     * @param users List of users to update the allowlist.
     * @param isAllowedList List of booleans to set the allowlist status.
     */
    function updateFixedTermDepositAllowlist(
        address lendingPool,
        uint256 configId,
        address[] calldata users,
        bool[] calldata isAllowedList
    ) external onlyLendingPoolManager {
        _verifyConfigId(lendingPool, configId);

        if (users.length != isAllowedList.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < users.length; ++i) {
            if (fixedTermDepositsAllowlist[lendingPool][configId][users[i]] != isAllowedList[i]) {
                fixedTermDepositsAllowlist[lendingPool][configId][users[i]] = isAllowedList[i];

                emit FixedTermDepositUserAllowlistUpdated(lendingPool, configId, users[i], isAllowedList[i]);
            }
        }
    }

    /**
     * @notice End a fixed term deposit for a lending pool early.
     * @dev Cannot be called during clearing time.
     * This should only be called by the lending pool manager.
     * User gets returned the tranche shares.
     * @param lendingPool Lending pool address.
     * @param fixedTermDepositId Id of the fixed term deposit.
     * @param arrayIndex Index of the fixed term deposit in the array.
     */
    function endFixedTermDeposit(address lendingPool, uint256 fixedTermDepositId, uint256 arrayIndex)
        external
        onlyLendingPoolManager
        verifyFixedDepositId(lendingPool, fixedTermDepositId)
        verifyClearingNotPending(lendingPool)
    {
        uint256 lendingPoolFixedTermDepositIdsLength = _lendingPoolFixedTermDepositIds[lendingPool].length;
        if (
            arrayIndex >= lendingPoolFixedTermDepositIdsLength
                || _lendingPoolFixedTermDepositIds[lendingPool][arrayIndex] != fixedTermDepositId
        ) {
            for (uint256 i; i < lendingPoolFixedTermDepositIdsLength; ++i) {
                if (_lendingPoolFixedTermDepositIds[lendingPool][i] == fixedTermDepositId) {
                    arrayIndex = i;
                    break;
                }
            }
        }

        UserLendingPoolFixedTermDeposit memory deposit =
            _lendingPoolFixedTermDepositFromArrayIndex(lendingPool, arrayIndex);

        FixedTermDepositConfig memory depositConfig =
            _lendingPoolFixedTermDepositConfigurations[lendingPool][deposit.fixedTermDepositConfigId];
        _endFixedTermDeposit(deposit, lendingPool, depositConfig.tranche, arrayIndex);
    }

    /**
     * @notice Lock a fixed term deposit automatically.
     * @dev This should only be called by the pending pool contract during the clearing process when user deposit is accepted.
     * @param user User address.
     * @param lendingPool Lending pool address.
     * @param tranche Tranche address.
     * @param trancheShares Amount of tranche shares to lock.
     * @param configId Id of the fixed term deposit configuration.
     * @param epochNumber Epoch number.
     */
    function lockFixedTermDepositAutomatically(
        address user,
        address lendingPool,
        address tranche,
        uint256 trancheShares,
        uint256 configId,
        uint256 epochNumber
    ) external verifyPendingPool(lendingPool, msg.sender) {
        _lockFixTermDeposit(user, lendingPool, tranche, trancheShares, configId, epochNumber);
    }

    /**
     * @notice Lock a fixed term deposit manually.
     * @dev This is called by the user to manually lock already owned tranche shares for a fixed term deposit.
     * Cannot be called during clearing time.
     * @param user User address.
     * @param lendingPool Lending pool address.
     * @param tranche Tranche address.
     * @param trancheShares Amount of tranche shares to lock.
     * @param configId Id of the fixed term deposit configuration.
     */
    function lockFixedTermDepositManually(
        address user,
        address lendingPool,
        address tranche,
        uint256 trancheShares,
        uint256 configId
    ) external onlyLendingPoolManager verifyTranche(lendingPool, tranche) verifyClearingNotPending(lendingPool) {
        verifyFixedTermDepositParameters(user, lendingPool, tranche, configId);
        _lockFixTermDeposit(user, lendingPool, tranche, trancheShares, configId, _systemVariables.currentEpochNumber());
    }

    /**
     * @notice Apply fixed term interests to the fixed term deposits.
     * @dev This should only be called by the clearing coordinator.
     * Calls lending pool to apply the fixed rate interests to the fixed term deposits.
     * Lending pool calculated the difference of the base interest rate and the fixed rate interest and mints or burns tranche shares accordingly.
     * @param lendingPool Lending pool address.
     * @param targetEpoch Epoch number to apply the interests.
     * @param batchSize Amount of fixed term deposits to process in this transaction.
     */
    function applyFixedTermInterests(address lendingPool, uint256 targetEpoch, uint256 batchSize)
        external
        onlyClearingCoordinator
    {
        if (_fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].status == TaskStatus.UNINITIALIZED) {
            _initializeLendingPoolFixedTermDepositsProcessing(lendingPool, targetEpoch);

            if (_fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].status == TaskStatus.ENDED) {
                return;
            }
        } else if (_fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].status == TaskStatus.ENDED) {
            revert FixedTermDepositsAlreadyProcessed(lendingPool, targetEpoch);
        }

        if (batchSize == 0) {
            return;
        }

        uint256 endingIndexInclusive;
        uint256 i;
        {
            uint256 nextIndexToProcess = _fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].nextIndexToProcess;
            if (batchSize <= nextIndexToProcess) {
                unchecked {
                    endingIndexInclusive = nextIndexToProcess - (batchSize - 1);
                }
            }
            i = nextIndexToProcess;
        }

        uint256[] storage depositIds = _lendingPoolFixedTermDepositIds[lendingPool];

        while (i >= endingIndexInclusive) {
            UserLendingPoolFixedTermDeposit memory deposit = _lendingPoolFixedTermDepositFromArrayIndex(lendingPool, i);

            FixedTermDepositConfig memory depositConfig =
                _lendingPoolFixedTermDepositConfigurations[lendingPool][deposit.fixedTermDepositConfigId];

            // user locked tranche shares
            uint256 trancheShares = deposit.trancheShares;

            uint256 trancheBalanceBefore = ILendingPoolTranche(depositConfig.tranche).balanceOf(address(this));

            ILendingPool(lendingPool).applyFixedRateInterests(
                deposit.user, depositConfig.tranche, trancheShares, depositConfig.epochInterestRate, targetEpoch
            );

            uint256 trancheBalanceAfter = ILendingPoolTranche(depositConfig.tranche).balanceOf(address(this));

            uint256 userTrancheSharesAfter = trancheShares;
            if (trancheBalanceAfter > trancheBalanceBefore) {
                // add tranche shares to the user lock

                userTrancheSharesAfter = trancheShares + trancheBalanceAfter - trancheBalanceBefore;
            } else if (trancheBalanceAfter < trancheBalanceBefore) {
                // remove tranche shares from the user lock
                uint256 trancheSharesToReturn = trancheBalanceBefore - trancheBalanceAfter;

                if (trancheSharesToReturn > trancheShares) {
                    // revert cannot burn more shares that the user deposit owns
                    // this should never happen
                    revert BadFixedTermDepositSharesBurned(
                        lendingPool, depositIds[i], trancheSharesToReturn, trancheShares
                    );
                }

                userTrancheSharesAfter = trancheShares - trancheSharesToReturn;
            }

            if (trancheShares != userTrancheSharesAfter) {
                // update user locked tranche shares
                _lendingPoolFixedTermDepositIdToLock[lendingPool][depositIds[i]].trancheShares = userTrancheSharesAfter;

                emit FixedTermDepositInterestApplied(lendingPool, depositIds[i], targetEpoch, userTrancheSharesAfter);
            }

            // check if the locked time has expired
            if (deposit.epochUnlockNumber <= targetEpoch) {
                // update memory deposit with the new tranche shares
                deposit.trancheShares = userTrancheSharesAfter;
                _endFixedTermDeposit(deposit, lendingPool, depositConfig.tranche, i);

                // check if the user has signaled to withdraw
                if (deposit.withdrawRequested && userTrancheSharesAfter > 0) {
                    // request a priority withdraw
                    IPendingPool(ILendingPool(lendingPool).pendingPool()).requestPriorityWithdrawal(
                        deposit.user, depositConfig.tranche, userTrancheSharesAfter, targetEpoch
                    );
                }
            }

            // if we've processed all requests, we can end the task
            if (i == 0) {
                _fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].status = TaskStatus.ENDED;
                break;
            }

            unchecked {
                --i;
            }
        }

        _fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch].nextIndexToProcess = i;
    }

    /**
     * @notice Request a fixed term deposit withdrawal.
     * @dev The request can be made only if the withdrawal request is not too late according to the withdrawal configuration.
     * @param user User address.
     * @param lendingPool Lending pool address.
     * @param fixedTermDepositId Id of the fixed term deposit.
     */
    function requestFixedTermDepositWithdrawal(address user, address lendingPool, uint256 fixedTermDepositId)
        external
        onlyLendingPoolManager
        verifyFixedDepositId(lendingPool, fixedTermDepositId)
        verifyFixedDepositUser(user, lendingPool, fixedTermDepositId)
    {
        UserLendingPoolFixedTermDeposit storage deposit =
            _lendingPoolFixedTermDepositIdToLock[lendingPool][fixedTermDepositId];

        if (deposit.withdrawRequested) {
            revert FixedTermDepositWithdrawalAlreadyRequested(lendingPool, fixedTermDepositId);
        }

        // check if the withdrawal request is too late
        uint256 currentEpoch = _systemVariables.currentRequestEpoch();
        if (
            _verifyWithdrawalActionTime(
                currentEpoch,
                deposit.epochUnlockNumber,
                _lendingPoolWithdrawalConfiguration[lendingPool].requestEpochsInAdvance
            )
        ) {
            revert FixedTermDepositWithdrawalRequestTooLate(
                lendingPool,
                fixedTermDepositId,
                _lendingPoolWithdrawalConfiguration[lendingPool].requestEpochsInAdvance,
                deposit.epochUnlockNumber,
                currentEpoch
            );
        }

        deposit.withdrawRequested = true;

        emit FixedTermDepositWithdrawalRequested(user, lendingPool, fixedTermDepositId);
    }

    /**
     * @notice Cancel a fixed term deposit withdrawal request.
     * @dev The request can be canceled only if the withdrawal request is not too late according to the withdrawal configuration.
     * @param user User address.
     * @param lendingPool Lending pool address.
     * @param fixedTermDepositId Id of the fixed term deposit.
     */
    function cancelFixedTermDepositWithdrawalRequest(address user, address lendingPool, uint256 fixedTermDepositId)
        external
        onlyLendingPoolManager
        verifyFixedDepositId(lendingPool, fixedTermDepositId)
        verifyFixedDepositUser(user, lendingPool, fixedTermDepositId)
    {
        UserLendingPoolFixedTermDeposit storage deposit =
            _lendingPoolFixedTermDepositIdToLock[lendingPool][fixedTermDepositId];

        if (!deposit.withdrawRequested) {
            revert FixedTermDepositWithdrawalNotRequested(lendingPool, fixedTermDepositId);
        }

        // check if the user can still cancel the request
        uint256 currentEpoch = _systemVariables.currentRequestEpoch();
        if (
            _verifyWithdrawalActionTime(
                currentEpoch,
                deposit.epochUnlockNumber,
                _lendingPoolWithdrawalConfiguration[lendingPool].cancelRequestEpochsInAdvance
            )
        ) {
            revert FixedTermDepositWithdrawalRequestCancelTooLate(
                lendingPool,
                fixedTermDepositId,
                _lendingPoolWithdrawalConfiguration[lendingPool].cancelRequestEpochsInAdvance,
                deposit.epochUnlockNumber,
                currentEpoch
            );
        }

        deposit.withdrawRequested = false;

        emit FixedTermDepositWithdrawalRequestCancelled(user, lendingPool, fixedTermDepositId);
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _lockFixTermDeposit(
        address user,
        address lendingPool,
        address tranche,
        uint256 trancheShares,
        uint256 configId,
        uint256 epochNumber
    ) private {
        ILendingPoolTranche(tranche).transferFrom(user, address(this), trancheShares);

        uint256 epochLockEnd =
            epochNumber + _lendingPoolFixedTermDepositConfigurations[lendingPool][configId].epochLockDuration;

        uint256 fixedTermDepositId = _lendingPoolFixedTermDepositNextId[lendingPool];
        _lendingPoolFixedTermDepositNextId[lendingPool]++;

        _lendingPoolFixedTermDepositIdToLock[lendingPool][fixedTermDepositId] = UserLendingPoolFixedTermDeposit({
            user: user,
            fixedTermDepositConfigId: uint16(configId),
            epochLockNumber: uint32(epochNumber),
            epochUnlockNumber: uint32(epochLockEnd),
            withdrawRequested: false,
            trancheShares: trancheShares
        });

        _lendingPoolFixedTermDepositIds[lendingPool].push(fixedTermDepositId);

        emit FixedTermDepositLocked(
            user, lendingPool, fixedTermDepositId, configId, tranche, trancheShares, epochNumber, epochLockEnd
        );
    }

    function _initializeLendingPoolFixedTermDepositsProcessing(address lendingPool, uint256 targetEpoch) private {
        uint256 totalFixedTermDeposits = _lendingPoolFixedTermDepositIds[lendingPool].length;

        FixedTermDepositsEpoch storage fixedTermDepositsEpoch =
            _fixedTermDepositsClearingPerEpoch[lendingPool][targetEpoch];
        if (totalFixedTermDeposits == 0) {
            fixedTermDepositsEpoch.status = TaskStatus.ENDED;
        } else {
            unchecked {
                fixedTermDepositsEpoch.nextIndexToProcess = totalFixedTermDeposits - 1;
            }
            fixedTermDepositsEpoch.status = TaskStatus.PENDING;
        }
    }

    function _endFixedTermDeposit(
        UserLendingPoolFixedTermDeposit memory deposit,
        address lendingPool,
        address tranche,
        uint256 i
    ) private {
        uint256[] storage depositIds = _lendingPoolFixedTermDepositIds[lendingPool];

        // send shares back to the user
        ILendingPoolTranche(tranche).transfer(deposit.user, deposit.trancheShares);

        uint256 depositId = depositIds[i];

        emit FixedTermDepositEnded(lendingPool, depositId);

        // remove deposit from the list
        delete _lendingPoolFixedTermDepositIdToLock[lendingPool][depositId];
        uint256 depositIdsLastIndex = depositIds.length - 1;
        if (i < depositIdsLastIndex) {
            // can be unchecked as we already checked the same calculation in the if statement
            unchecked {
                depositIds[i] = depositIds[depositIdsLastIndex];
            }
        }
        depositIds.pop();
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _lendingPoolFixedTermDepositFromArrayIndex(address lendingPool, uint256 arrayIndex)
        private
        view
        returns (UserLendingPoolFixedTermDeposit storage)
    {
        return _lendingPoolFixedTermDeposit(lendingPool, _lendingPoolFixedTermDepositIds[lendingPool][arrayIndex]);
    }

    function _lendingPoolFixedTermDeposit(address lendingPool, uint256 id)
        private
        view
        returns (UserLendingPoolFixedTermDeposit storage)
    {
        return _lendingPoolFixedTermDepositIdToLock[lendingPool][id];
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _verifyWithdrawalActionTime(uint256 currentEpoch, uint256 unlockEpoch, uint256 requestEpochsInAdvance)
        private
        view
        returns (bool isTooLate)
    {
        if (currentEpoch < unlockEpoch) {
            unchecked {
                if (requestEpochsInAdvance > unlockEpoch - currentEpoch) {
                    isTooLate = true;
                }
            }
        } else if (currentEpoch == unlockEpoch) {
            if (requestEpochsInAdvance != 0 || _systemVariables.isClearingTime()) {
                isTooLate = true;
            }
        } else {
            isTooLate = true;
        }
    }

    function _verifyConfigId(address lendingPool, uint256 configId) private view {
        if (configId == 0 || lendingPoolFixedTermDepositConfigCount[lendingPool] < configId) {
            revert InvalidConfiguration();
        }
    }

    function _verifyTrancheInterestRate(uint256 interestRate) private view {
        if (interestRate == 0 || interestRate > _systemVariables.maxTrancheInterestRate()) {
            revert InvalidConfiguration();
        }
    }

    function _verifyTranche(address lendingPool, address tranche) private view {
        if (!ILendingPool(lendingPool).isLendingPoolTranche(tranche)) {
            revert ILendingPoolErrors.InvalidTranche(lendingPool, tranche);
        }
    }

    function _verifyFixedTermDepositId(address lendingPool, uint256 id) private view {
        if (id >= _lendingPoolFixedTermDepositNextId[lendingPool]) {
            revert InvalidFixedTermDepositId(lendingPool, id);
        }

        if (_lendingPoolFixedTermDepositIdToLock[lendingPool][id].user == address(0)) {
            revert InvalidFixedTermDepositId(lendingPool, id);
        }
    }

    function _verifyFixedTermDepositUser(address user, address lendingPool, uint256 id) private view {
        if (_lendingPoolFixedTermDepositIdToLock[lendingPool][id].user != user) {
            revert InvalidLendingPoolFixedTermDepositUser(lendingPool, id, user);
        }
    }

    function _onlyLendingPoolManager() private view {
        if (msg.sender != address(_lendingPoolManager)) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }
    }

    function _verifyClearingNotPending(address lendingPool) private view {
        if (_clearingCoordinator.isLendingPoolClearingPending(lendingPool)) {
            revert ILendingPoolErrors.ClearingIsPending();
        }
    }

    function _onlyClearingCoordinator() private view {
        if (msg.sender != address(_clearingCoordinator)) {
            revert ILendingPoolErrors.OnlyClearingCoordinator();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier verifyFixedDepositId(address lendingPool, uint256 id) {
        _verifyFixedTermDepositId(lendingPool, id);
        _;
    }

    modifier verifyFixedDepositUser(address user, address lendingPool, uint256 id) {
        _verifyFixedTermDepositUser(user, lendingPool, id);
        _;
    }

    modifier onlyLendingPoolManager() {
        _onlyLendingPoolManager();
        _;
    }

    modifier onlyClearingCoordinator() {
        _onlyClearingCoordinator();
        _;
    }

    modifier verifyPendingPool(address lendingPool, address pendingPool) {
        if (
            !ILendingPoolManager(_lendingPoolManager).isLendingPool(lendingPool)
                || !(ILendingPool(lendingPool).pendingPool() == pendingPool)
        ) {
            revert OnlyPendingPool();
        }
        _;
    }

    modifier verifyTranche(address lendingPool, address tranche) {
        _verifyTranche(lendingPool, tranche);
        _;
    }

    modifier verifyClearingNotPending(address lendingPool) {
        _verifyClearingNotPending(lendingPool);
        _;
    }
}
