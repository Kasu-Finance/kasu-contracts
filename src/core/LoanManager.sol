// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "./interfaces/ILoanManager.sol";
import "./interfaces/ILoanImpairments.sol";

abstract contract LendingPoolManager is ILoanManager, ILoanImpairments {
    mapping(uint256 => Loan) private lendingPoolLoans;

    function addLoans(address lendingPool, Loan[] calldata loans) external returns (uint256) {
        revert("0");
    }

    function removeLoans(uint256[] calldata loanIDs) external {
        revert ("0");
    }

    function reportLoss(Loss[] calldata loss) external {
        revert("0");
    }

    function makePayment(LoanPayment[] calldata payments) external {
        revert("0");
    }

    function lendingPoolLoan(address lendingPool, uint256 loanlID) external view returns (Loan memory) {
        revert("0");
    }

    function lendingPoolLoansArray(address lendingPool) external view returns (Loan[] memory) {
        revert("0");
    }
}
