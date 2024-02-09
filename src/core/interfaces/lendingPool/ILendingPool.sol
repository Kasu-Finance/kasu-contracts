// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// TODO: should I add most lending pool data here?
struct LendingPoolInfo {
    TrancheData[] tranches;
    address pendingPool;
    // TODO: should I update this instead of LendingPool.firstLossCapital ?
    uint256 firstLossCapital;
    // TODO: should I update this ?
    uint256 totalBalance;
    uint256 excessFunds;
    uint256 excessTargetLiquidity; // percentage of not borrowed funds (only as senior deposits)
}

struct TrancheData {
    address trancheAddress;
    uint256 ratio;
    uint256 interestRate;
}

/**
 * @notice Interface for the LendingPool contract.
 */
interface ILendingPool is IERC20 {
    function getPendingPool() external view returns (address);

    function lendingPoolInfo() external view returns (LendingPoolInfo memory);

    // #### CLEARING #### //
    function acceptDeposit(address tranche, address user, uint256 acceptedAmount) external;

    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        returns (uint256 assetAmount);

    // #### POOL DELEGATE #### //
    function borrowLoan(uint256 amount) external;

    function repayLoan(uint256 amount, address repaymentAddress) external;

    //     function updateLoanAmount(uint256 amount) external;

    function reportLoss(uint256 lossAmount) external returns (uint256 lossId);

    //     function repayLoss(uint256 lossId, uint256 amount) external;

    function depositFirstLossCapital(uint256 amount) external;

    function withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress) external;

    function forceImmediateWithdrawal(address tranche, address user, uint256 sharesToWithdraw)
        external
        returns (uint256 assetAmount);

    function stop(address firstLossCapitalReceiver) external;

    //     // #### PROTOCOL FEES #### //
    //     function withdrawProtocolFees() external;

    // Events
    event DepositAccepted(address indexed user, address indexed tranche, uint256 amount);

    event WithdrawalAccepted(address indexed user, address indexed tranche, uint256 shares);

    event ImmediateWithdrawal(address indexed user, address indexed tranche, uint256 shares, uint256 amount);

    event LoanBorrowed(uint256 amount);

    event LoanRepaid(uint256 amount);

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
}
