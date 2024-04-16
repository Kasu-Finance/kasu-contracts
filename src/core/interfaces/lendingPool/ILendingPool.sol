// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ILendingPoolFactory.sol";

/**
 * @notice Lending pool address information.
 * @custom:member trancheAddresses Tranche addresses.
 * @custom:member pendingPool Pending pool address.
 */
struct LendingPoolInfo {
    address[] trancheAddresses;
    address pendingPool;
}

/**
 * @notice Lending pool configuration.
 * @custom:member tranches Tranche configurations.
 * @custom:member drawRecipient Address to receive the funds drawn from the pool.
 * @custom:member desiredDrawAmount Desired draw amount at the next clearing.
 * @custom:member trancheInterestChangeEpochDelay Delay in epochs for tranche interest rate changes.
 * @custom:member targetExcessLiquidityPercentage Target excess liquidity percentage.
 * @custom:member minimumExcessLiquidityPercentage Minimum excess liquidity percentage. Used for calculating maximum accepted withdrawal amount when clearing.
 */
struct PoolConfiguration {
    TrancheConfig[] tranches;
    address drawRecipient;
    uint256 desiredDrawAmount;
    uint256 trancheInterestChangeEpochDelay;
    uint256 targetExcessLiquidityPercentage;
    uint256 minimumExcessLiquidityPercentage;
}

/**
 * @notice Lending pool tranche configuration.
 * @custom:member ratio Tranche ratio. 100% is 1e5. All tranche ratios should sum up to 100%.
 * @custom:member interestRate Tranche interest rate. 100% is 1e18.
 * @custom:member minDepositAmount Minimum tranche deposit request amount.
 * @custom:member maxDepositAmount Maximum tranche deposit request amount.
 */
struct TrancheConfig {
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

interface ILendingPool is IERC20 {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function userOwedAmount() external view returns (uint256);
    function feesOwedAmount() external view returns (uint256);
    function pendingPool() external view returns (address);
    function userBalance(address user) external view returns (uint256);
    function lendingPoolInfo() external view returns (LendingPoolInfo memory);
    function poolConfiguration() external view returns (PoolConfiguration memory);
    function trancheConfigurationDepositLimits(address tranche)
        external
        view
        returns (uint256 minDepositAmount, uint256 maxDepositAmount);
    function isLendingPoolTranche(address tranche) external view returns (bool);
    function trancheIndex(address tranche) external view returns (uint256);
    function lendingPoolTranches() external view returns (address[] memory);
    function lendingPoolTrancheCount() external view returns (uint256);
    function availableFunds() external view returns (uint256);
    function clearingConfiguration() external view returns (ClearingConfiguration memory clearingConfig);
    function verifyClearingConfig(ClearingConfiguration calldata clearingConfig) external view;
    function calculateMaximumLossAmount() external view returns (uint256 maximumLossAmount);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // #### CLEARING #### //
    function acceptDeposit(address tranche, address user, uint256 acceptedAmount)
        external
        returns (uint256 trancheShares);
    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        returns (uint256 assetAmount);
    function applyInterests(uint256 epoch) external;
    function payOwedFees() external;

    // #### USER #### //

    function claimRepaidLoss(address user, address tranche, uint256 lossId) external returns (uint256 claimedAmount);

    // #### POOL MANAGEMENT #### //
    function drawFunds(uint256 amount) external;
    function repayOwedFunds(uint256 amount) external;
    function reportLoss(uint256 lossAmount, bool doMintLossTokens) external returns (uint256 appliedLoss);
    function repayLoss(address tranche, uint256 lossId, uint256 amount) external;
    function depositFirstLossCapital(uint256 amount) external;
    function withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress) external;
    function forceImmediateWithdrawal(address tranche, address user, uint256 sharesToWithdraw)
        external
        returns (uint256 assetAmount);
    function stop() external;

    // #### POOL CONFIG #### //

    function updateDrawRecipient(address drawRecipient) external;
    function updateMinimumDepositAmount(address tranche, uint256 minimumDepositAmount) external;
    function updateMaximumDepositAmount(address tranche, uint256 maximumDepositAmount) external;
    function updateTrancheInterestRate(address tranche, uint256 interestRate) external;
    function updateTrancheDesiredRatios(uint256[] calldata ratios) external;
    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external;
    function updateDesiredDrawAmount(uint256 desiredDrawAmount) external;
    function updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage) external;
    function updateMinimumExcessLiquidityPercentage(uint256 minimumExcessLiquidityPercentage) external;

    /* ========== EVENTS ========== */

    event DepositAccepted(address indexed user, address indexed tranche, uint256 amount);
    event WithdrawalAccepted(address indexed user, address indexed tranche, uint256 shares, uint256 assetAmount);
    event ImmediateWithdrawal(address indexed user, address indexed tranche, uint256 shares, uint256 amount);
    event FundsDrawn(uint256 amount);
    event OwedFundsRepaid(uint256 amountForUsers, uint256 amountForFees);
    event FirstLossCapitalLossReported(uint256 indexed lossId, uint256 amount);
    event LossReported(uint256 amount);
    event FirstLossCapitalAdded(uint256 amountAdded);
    event FirstLossCapitalWithdrawn(uint256 amountWithdrawn);
    event UpdatedTrancheInterestRate(address indexed tranche, uint256 indexed applicableEpoch, uint256 newInterestRate);
    event RemovedTrancheInterestRateUpdate(
        address indexed tranche, uint256 indexed applicableEpoch, uint256 arrayIndex
    );
    event InterestApplied(address indexed tranche, uint256 indexed epoch, uint256 interestAmount);
    event FeesOwedIncreased(uint256 indexed epoch, uint256 feesIncreasedAmount);
    event PaidFees(uint256 feesPaid);
    event PaidFeesFromAvailableFunds(uint256 feesPaid);
    event UpdatedDesiredDrawAmount(uint256 desiredDrawAmount);
    event UpdatedDrawRecipient(address indexed drawRecipient);
    event UpdatedTrancheInterestRateChangeEpochDelay(uint256 epochDelay);
    event LendingPoolStopped();
    event UpdatedMinimumDepositAmount(address indexed tranche, uint256 amount);
    event UpdatedMaximumDepositAmount(address indexed tranche, uint256 amount);
    event UpdatedTrancheDesiredRatios(uint256[] ratios);
    event UpdatedTargetExcessLiquidityPercentage(uint256 percentage);
    event UpdatedMinimumExcessLiquidityPercentage(uint256 percentage);

    /* ========== ERRORS ========== */

    error DrawAmountCantBeGreaterThanAvailableAmount(uint256 drawAmount, uint256 availableAmount);
    error RepayAmountCantBeGreaterThanOwedAmount(uint256 repayAmount, uint256 owedAmount);
    error WithdrawAmountCantBeGreaterThanFirstLostCapital(uint256 withdrawAmount, uint256 firstLostCapital);
    error LossAmountCantBeGreaterThanMaxLossAmount(uint256 reportedLossAmount, uint256 maxLossAmount);
    error LossAmountShouldBeGreaterThanZero(uint256 reportedLossAmount);
    error UserOwedAmountIsGreaterThanZero(uint256 userOwedAmount);
    error FeesOwedAmountIsGreaterThanZero(uint256 feesOwedAmount);
    error LendingPoolIsStopped();
    error LendingPoolIsNotStopped();
    error PoolConfigurationIsIncorrect(string reason);
    error LossIdNotValid(uint256 lossId);
    error ClearingIsPending();
}
