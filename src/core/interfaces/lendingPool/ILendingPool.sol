// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ILendingPoolFactory.sol";

struct LendingPoolInfo {
    address[] trancheAddresses;
    address pendingPool;
}

struct TrancheConfig {
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

struct PoolConfiguration {
    TrancheConfig[] tranches;
    address drawRecipient;
    uint256 desiredDrawAmount;
    uint256 trancheInterestChangeEpochDelay;
    uint256 targetExcessLiquidityPercentage;
    uint256 minimumExcessLiquidityPercentage;
}

/**
 * @notice Interface for the LendingPool contract.
 */
interface ILendingPool is IERC20 {
    function getPendingPool() external view returns (address);

    function getUserBalance(address user) external view returns (uint256);

    function getlendingPoolInfo() external view returns (LendingPoolInfo memory);

    function poolConfiguration() external view returns (PoolConfiguration memory);

    function trancheConfigurationDepositLimits(address tranche)
        external
        view
        returns (uint256 minDepositAmount, uint256 maxDepositAmount);

    function isLendingPoolTranche(address tranche) external view returns (bool);

    function getTrancheIndex(address tranche) external view returns (uint256);

    function getLendingPoolTranches() external view returns (address[] memory);

    function getLendingPoolTrancheCount() external view returns (uint256);

    function getUserOwedAmount() external view returns (uint256);

    function getFeesOwedAmount() external view returns (uint256);

    function getAvailableFunds() external view returns (uint256);

    function getMaximumLossAmount() external view returns (uint256 maximumLossAmount);

    // #### CLEARING #### //
    function acceptDeposit(address tranche, address user, uint256 acceptedAmount)
        external
        returns (uint256 trancheShares);

    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        returns (uint256 assetAmount);

    function applyInterests(uint256 epoch) external;

    function verifyClearingConfig(ClearingConfiguration calldata clearingConfig) external view;

    function getClearingConfig() external view returns (ClearingConfiguration memory clearingConfig);

    // #### POOL DELEGATE #### //
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

    // #### USER #### //

    function claimRepaidLoss(address user, address tranche, uint256 lossId) external returns (uint256 claimedAmount);

    // #### CONFIG #### //

    function updateDrawRecipient(address drawRecipient) external;

    function updateMinimumDepositAmount(address tranche, uint256 minimumDepositAmount) external;

    function updateMaximumDepositAmount(address tranche, uint256 maximumDepositAmount) external;

    function updateTrancheInterestRate(address tranche, uint256 interestRate) external;

    function updateTrancheDesiredRatios(uint256[] calldata ratios) external;

    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external;

    function updateDesiredDrawAmount(uint256 desiredDrawAmount) external;

    function updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage) external;

    function updateMinimumExcessLiquidityPercentage(uint256 minimumExcessLiquidityPercentage) external;

    // Events
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

    event UpdatedDesiredDrawAmount(uint256 desiredDrawAmount);

    event UpdatedDrawRecipient(address indexed drawRecipient);

    event UpdatedTrancheInterestRateChangeEpochDelay(uint256 epochDelay);

    event LendingPoolStopped();

    event UpdatedMinimumDepositAmount(address indexed tranche, uint256 amount);

    event UpdatedMaximumDepositAmount(address indexed tranche, uint256 amount);

    event UpdatedTrancheDesiredRatios(uint256[] ratios);

    event UpdatedTargetExcessLiquidityPercentage(uint256 percentage);

    event UpdatedMinimumExcessLiquidityPercentage(uint256 percentage);

    // Errors

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
