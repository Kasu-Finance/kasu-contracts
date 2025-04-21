// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IPendingPool.sol";
import "./ILendingPool.sol";
import "./ILendingPoolFactory.sol";
import "./IFixedTermDeposit.sol";

struct KycData {
    uint256 blockExpiration;
    bytes signature;
}

interface ILendingPoolManager {
    function isLendingPool(address lendingPool) external view returns (bool);

    // #### USER #### //
    function requestDeposit(
        address lendingPool,
        address tranche,
        uint256 maxAmount,
        bytes calldata swapData,
        uint256 fixedTermConfigId,
        bytes calldata depositData
    ) external payable returns (uint256 dNftID);
    function requestDepositWithKyc(
        address lendingPool,
        address tranche,
        uint256 maxAmount,
        bytes calldata swapData,
        uint256 fixedTermConfigId,
        bytes calldata depositData,
        KycData calldata kycData
    ) external payable returns (uint256 dNftID);
    function cancelDepositRequest(address lendingPool, uint256 dNftID) external;
    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        returns (uint256 wNftID);
    function cancelWithdrawalRequest(address lendingPool, uint256 wNftID) external;
    function claimRepaidLoss(address lendingPool, address tranche, uint256 lossId)
        external
        returns (uint256 claimedAmount);
    function lockDepositForFixedTerm(address lendingPool, address tranche, uint256 amount, uint256 fixedTermConfigId)
        external;
    function requestFixedTermDepositWithdrawal(address lendingPool, uint256 fixedTermDepositId) external;
    function cancelFixedTermDepositWithdrawalRequest(address lendingPool, uint256 fixedTermDepositId) external;

    // #### LENDING POOL CREATOR #### //
    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment);

    // #### POOL ADMIN #### //

    function updateDrawRecipient(address lendingPool, address drawRecipient) external;

    // #### POOL FUNDS MANAGER #### //

    function reportLoss(address lendingPool, uint256 amount, bool doMintLossTokens) external returns (uint256 lossId);
    function repayOwedFunds(address lendingPool, uint256 amount, address repaymentAddress) external;
    function repayLoss(address lendingPool, address tranche, uint256 lossId, uint256 amount) external;
    function depositFirstLossCapital(address lendingPool, uint256 amount) external;
    function withdrawFirstLossCapital(address lendingPool, uint256 withdrawAmount, address withdrawAddress) external;

    // #### POOL CLEARING MANAGER #### //

    function doClearing(
        address lendingPool,
        uint256 targetEpoch,
        uint256 fixedTermDepositBatchSize,
        uint256 priorityCalculationBatchSize,
        uint256 acceptRequestsBatchSize,
        ClearingConfiguration calldata clearingConfigOverride,
        bool isConfigOverridden
    ) external;

    // #### POOL MANAGER #### //

    function forceImmediateWithdrawal(address lendingPool, address tranche, address user, uint256 sharesToWithdraw)
        external
        returns (uint256);
    function batchForceWithdrawals(address lendingPool, ForceWithdrawalInput[] calldata input)
        external
        returns (uint256[] memory);
    function forceCancelDepositRequest(address lendingPool, uint256 dNftID) external;
    function forceCancelWithdrawalRequest(address lendingPool, uint256 wNftID) external;
    function forceAcceptWithdrawalRequest(address lendingPool, uint256 wNftID, uint256 acceptedShares) external;
    function endFixedTermDeposit(address lendingPool, uint256 fixedTermDepositId, uint256 arrayIndex) external;
    function stopLendingPool(address lendingPool) external;

    // #### POOL CONFIG #### //

    function updateTargetExcessLiquidityPercentage(address lendingPool, uint256 targetExcessLiquidityPercentage)
        external;
    function updateMinimumExcessLiquidityPercentage(address lendingPool, uint256 minimumExcessLiquidityPercentage)
        external;
    function updateMinimumDepositAmount(address lendingPool, address tranche, uint256 minimumDepositAmount) external;
    function updateMaximumDepositAmount(address lendingPool, address tranche, uint256 maximumDepositAmount) external;
    function updateTrancheInterestRate(address lendingPool, address tranche, uint256 interestRate) external;
    function updateDesiredDrawAmount(address lendingPool, uint256 amount) external;
    function updateTrancheDesiredRatios(address lendingPool, uint256[] calldata ratios) external;
    function updateTrancheInterestRateChangeEpochDelay(address lendingPool, uint256 epochDelay) external;
    function addLendingPoolTrancheFixedTermDeposit(
        address lendingPool,
        address tranche,
        uint256 epochLockDuration,
        uint256 epochInterestRate,
        bool whitelistedOnly
    ) external returns (uint256 fixedTermConfigId);
    function updateLendingPoolTrancheFixedInterestStatus(
        address lendingPool,
        uint256 fixedTermConfigId,
        FixedTermDepositStatus fixedTermDepositStatus
    ) external;
    function updateLendingPoolWithdrawalConfiguration(
        address lendingPool,
        LendingPoolWithdrawalConfiguration calldata withdrawalConfiguration
    ) external;
    function updateFixedTermDepositAllowlist(
        address lendingPool,
        uint256 configId,
        address[] calldata users,
        bool[] calldata isAllowedList
    ) external;

    /* ========== EVENTS ========== */

    event DepositDataAdded(address indexed lendingPool, uint256 indexed dNftID, bytes data);
}
