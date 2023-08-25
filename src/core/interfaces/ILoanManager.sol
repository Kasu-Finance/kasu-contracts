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

// mapping (address => Loan[]) _loans;

interface ILoanManager {
    function addLoans(address lendingPool, Loan[] calldata loans) external returns (uint256);
    function removeLoans(uint256[] calldata loanIDs) external;
    function reportLoss(Loss[] calldata loss) external;
    function makePayment(LoanPayment[] calldata payments) external;

    function lendingPoolLoan(address lendingPool, uint256 loanlID) external view returns (Loan memory);
    function lendingPoolLoans(address lendingPool) external view returns (Loan[] memory);
}
