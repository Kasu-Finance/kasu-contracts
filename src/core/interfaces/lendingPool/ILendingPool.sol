// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ILendingPoolFactory.sol";

struct LendingPoolInfo {
    address[] trancheAddresses;
    address pendingPoolAddress;
}

struct TrancheConfig {
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

struct PoolConfiguration {
    uint256 targetExcessLiquidity;
    TrancheConfig[] tranches;
    address poolAdmin;
    address borrowRecipient;
    uint256 totalDesiredLoanAmount;
    uint256 trancheInterestChangeEpochDelay;
}

/**
 * @notice Interface for the LendingPool contract.
 */
interface ILendingPool is IERC20 {
    function getPendingPool() external view returns (address);

    function getUserBalance(address user) external view returns (uint256);

    function lendingPoolInfo() external view returns (LendingPoolInfo memory);

    function poolConfiguration() external returns (PoolConfiguration memory);

    // #### CLEARING #### //
    function acceptDeposit(address tranche, address user, uint256 acceptedAmount) external;

    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        returns (uint256 assetAmount);

    // #### POOL DELEGATE #### //
    function borrowLoan(uint256 amount) external;

    function repayLoan(uint256 amount, address repaymentAddress) external;

    //     function updateLoanAmount(uint256 amount) external;

    function reportLoss(uint256 lossAmount, bool doMintLossTokens) external returns (uint256 appliedLoss);

    function repayLoss(address tranche, uint256 lossId, uint256 amount) external;

    function depositFirstLossCapital(uint256 amount) external;

    function withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress) external;

    function forceImmediateWithdrawal(address tranche, address user, uint256 sharesToWithdraw)
        external
        returns (uint256 assetAmount);

    function stop(address firstLossCapitalReceiver) external;

    // #### USER #### //

    function claimRepaiedLoss(address user, address tranche, uint256 lossId) external returns (uint256 claimedAmount);

    // #### CONFIG #### //

    function updateMinimumDepositAmount(address tranche, uint256 minimumDepositAmount) external;

    function updateMaximumDepositAmount(address tranche, uint256 maximumDepositAmount) external;

    function updateTrancheInterestRate(address tranche, uint256 interestRate) external;

    function updateTrancheDesiredRatios(uint256[] calldata ratios) external;

    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external;

    function updateTotalDesiredLoanAmount(uint256 totalDesiredLoanAmount) external;

    // Events
    event DepositAccepted(address indexed user, address indexed tranche, uint256 amount);

    event WithdrawalAccepted(address indexed user, address indexed tranche, uint256 shares);

    event ImmediateWithdrawal(address indexed user, address indexed tranche, uint256 shares, uint256 amount);

    event LoanBorrowed(uint256 amount);

    event LoanRepaid(uint256 amount);

    event FirstLossCapitalLossReported(uint256 indexed lossId, uint256 amount);

    event LossReported(uint256 amount);

    event FirstLossCapitalAdded(uint256 amountAdded, uint256 newTotalAmount);

    event FirstLossCapitalWithdrawn(uint256 amountWithdrawn, uint256 newTotalAmount);

    // Errors

    error BorrowAmountCantBeGreaterThanAvailableAmount(uint256 borrowAmount, uint256 availableAmount);
    error RepayAmountCantBeGreaterThanBorrowedAmount(uint256 repayAmount, uint256 borrowedAmount);
    error WithdrawAmountCantBeGreaterThanFirstLostCapital(uint256 withdrawAmount, uint256 firstLostCapital);
    error LossAmountCantBeGreaterThanSupply(uint256 lossAmount, uint256 supply);
    error LossAmountShouldBeGreaterThanZero(uint256 lossAmount);
    error BorrowedAmountIsGreaterThanZero(uint256 borrowedAmoun);
    error LendingPoolIsStopped();
    error PoolConfigurationIsIncorrect(string reason);
    error LossIdNotValid(uint256 lossId);
}
