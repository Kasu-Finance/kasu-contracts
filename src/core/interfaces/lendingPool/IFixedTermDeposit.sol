// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {TaskStatus} from "../clearing/IClearingStepsData.sol";

/**
 * @notice Lending Pool withdrawal rules configuration.
 * @custom:member requestEpochsInAdvance Number of epochs in advance to request a withdrawal.
 * @custom:member cancelRequestEpochsInAdvance Number of epochs in advance to cancel a withdrawal request.
 */
struct LendingPoolWithdrawalConfiguration {
    uint128 requestEpochsInAdvance;
    uint128 cancelRequestEpochsInAdvance;
}

enum FixedTermDepositStatus {
    DISABLED,
    WHITELISTED_ONLY,
    EVERYONE
}

struct FixedTermDepositConfig {
    address tranche;
    uint64 epochInterestRate;
    uint16 epochLockDuration;
    FixedTermDepositStatus fixedTermDepositStatus;
}

struct UserLendingPoolFixedTermDeposit {
    address user;
    uint16 fixedTermDepositConfigId;
    uint32 epochLockNumber;
    uint32 epochUnlockNumber;
    bool withdrawRequested;
    uint256 trancheShares;
}

interface IFixedTermDeposit {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function verifyFixedTermDepositParameters(address user, address lendingPool, address tranche, uint256 configId)
        external
        view;

    function configIdTranche(address lendingPool, uint256 configId) external view returns (address tranche);

    function lendingPoolFixedTermConfig(address lendingPool, uint256 configId)
        external
        view
        returns (FixedTermDepositConfig memory);

    function lendingPoolFixedTermDepositConfigCount(address lendingPool) external view returns (uint256 configCount);

    function lendingPoolFixedTermDepositIds(address lendingPool) external view returns (uint256[] memory);

    function lendingPoolFixedTermDeposit(address lendingPool, uint256 fixedTermDepositId)
        external
        view
        returns (UserLendingPoolFixedTermDeposit memory);

    function lendingPoolWithdrawalConfiguration(address lendingPool)
        external
        view
        returns (LendingPoolWithdrawalConfiguration memory);

    function fixedTermDepositsAllowlist(address lendingPool, uint256 configId, address user)
        external
        view
        returns (bool isAllowed);

    function lendingPoolFixedTermDepositsCount(address lendingPool) external view returns (uint256);

    function fixedTermDepositsClearingPerEpochStatus(address lendingPool, uint256 epoch)
        external
        view
        returns (TaskStatus);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function addLendingPoolTrancheFixedTermDeposit(
        address lendingPool,
        address tranche,
        uint256 epochLockDuration,
        uint256 epochInterestRate,
        bool whitelistedOnly
    ) external returns (uint256 fixedTermConfigId);

    function updateLendingPoolWithdrawalConfiguration(
        address lendingPool,
        LendingPoolWithdrawalConfiguration calldata withdrawalConfiguration
    ) external;

    function updateLendingPoolTrancheFixedInterestStatus(
        address lendingPool,
        uint256 fixedTermConfigId,
        FixedTermDepositStatus fixedTermDepositStatus
    ) external;

    function updateFixedTermDepositAllowlist(
        address lendingPool,
        uint256 configId,
        address[] calldata users,
        bool[] calldata isAllowedList
    ) external;

    function endFixedTermDeposit(address lendingPool, uint256 fixedTermDepositId, uint256 arrayIndex) external;

    function applyFixedTermInterests(address lendingPool, uint256 targetEpoch, uint256 batchSize) external;

    function lockFixedTermDepositAutomatically(
        address user,
        address lendingPool,
        address tranche,
        uint256 trancheShares,
        uint256 configId,
        uint256 epochNumber
    ) external;

    function lockFixedTermDepositManually(
        address user,
        address lendingPool,
        address tranche,
        uint256 trancheShares,
        uint256 configId
    ) external;

    function requestFixedTermDepositWithdrawal(address user, address lendingPool, uint256 fixedTermDepositId)
        external;

    function cancelFixedTermDepositWithdrawalRequest(address user, address lendingPool, uint256 fixedTermDepositId)
        external;

    /* ========== EVENTS ========== */

    event LendingPoolTrancheLockInterestAdded(
        address indexed lendingPool,
        address indexed tranche,
        uint256 indexed configId,
        uint256 epochLockDuration,
        uint256 epochInterestRate,
        FixedTermDepositStatus fixedTermDepositStatus
    );

    event LendingPoolTrancheLockInterestStatusUpdated(
        address indexed lendingPool, uint256 indexed configId, FixedTermDepositStatus fixedTermDepositStatus
    );

    event LendingPoolWithdrawalConfigurationUpdated(
        address indexed lendingPool, LendingPoolWithdrawalConfiguration withdrawalConfiguration
    );

    event FixedTermDepositUserAllowlistUpdated(
        address indexed lendingPool, uint256 indexed configId, address indexed user, bool isAllowed
    );

    event FixedTermDepositLocked(
        address indexed user,
        address indexed lendingPool,
        uint256 indexed fixedTermDepositId,
        uint256 configId,
        address tranche,
        uint256 trancheShares,
        uint256 epochLockStart,
        uint256 epochLockEnd
    );

    event FixedTermDepositWithdrawalRequested(
        address indexed user, address indexed lendingPool, uint256 indexed fixedTermDepositId
    );

    event FixedTermDepositWithdrawalRequestCancelled(
        address indexed user, address indexed lendingPool, uint256 indexed fixedTermDepositId
    );

    event FixedTermDepositEnded(address indexed lendingPool, uint256 indexed fixedTermDepositId);

    event FixedTermDepositInterestApplied(
        address indexed lendingPool,
        uint256 indexed fixedTermDepositId,
        uint256 indexed targetEpoch,
        uint256 trancheSharesAfter
    );

    /* ========== ERRORS ========== */

    error OnlyPendingPool();
    error BadFixedTermDeposit(
        address lendingPool,
        address tranche,
        uint256 epochLockDuration,
        uint256 actualInterestRate,
        uint256 expectedInterestRate
    );
    error UserNotWhitelistedForFixedTermDeposit(address lendingPool, uint256 configId, address user);
    error FixedTermDepositDisabled(address lendingPool, uint256 configId);
    error InvalidTrancheForFixedTermDeposit(
        address lendingPool, uint256 configId, address configTranche, address requestedTranche
    );

    error InvalidFixedTermDepositId(address lendingPool, uint256 fixedTermDepositId);
    error InvalidLendingPoolFixedTermDepositUser(address lendingPool, uint256 fixedTermDepositId, address invalidUser);
    error FixedTermDepositWithdrawalAlreadyRequested(address lendingPool, uint256 fixedTermDepositId);

    error FixedTermDepositWithdrawalNotRequested(address lendingPool, uint256 fixedTermDepositId);
    error FixedTermDepositWithdrawalRequestTooLate(
        address lendingPool,
        uint256 fixedTermDepositId,
        uint256 requestEpochsInAdvance,
        uint256 epochUnlockNumber,
        uint256 currentEpoch
    );
    error FixedTermDepositWithdrawalRequestCancelTooLate(
        address lendingPool,
        uint256 fixedTermDepositId,
        uint256 cancelRequestEpochsInAdvance,
        uint256 epochUnlockNumber,
        uint256 currentEpoch
    );
    error FixedTermDepositsAlreadyProcessed(address lendingPool, uint256 targetEpoch);
    error BadFixedTermDepositSharesBurned(
        address lendingPool, uint256 fixedTermDepositId, uint256 actualSharesBurned, uint256 trancheShares
    );
}
