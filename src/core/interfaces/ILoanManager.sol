// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

struct Loan {
    uint256 amount;
    uint256 interestRate;
}

struct Loss {
    address lendingPool;
    uint256 loanID;
    uint256 amount;
}

struct LoanPayment {
    address lendingPool;
    uint256 loanID;
    uint256 amountPrincipal;
    uint256 amountYield;
}

interface ILoanManager {
    function addLoans(address lendingPool, Loan[] calldata loans) external returns (uint256);
    function removeLoans(address lendingPool, uint256[] calldata loanIDs) external;
    function reportLoss(Loss[] calldata loss) external;
    function makePayment(LoanPayment[] calldata payments) external;
}
