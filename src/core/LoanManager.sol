// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/ILoanManager.sol";
import "./interfaces/ILoanImpairments.sol";

contract LoanManager is ILoanManager, ILoanImpairments {
    mapping(uint256 => Loan) private lendingPoolLoans_;

    function addLoans(address lendingPool, Loan[] calldata loans) external returns (uint256) {
        revert("0");
    }

    function removeLoans(uint256[] calldata loanIDs) external {
        revert("0");
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

    function lendingPoolLoans(address lendingPool) external view override returns (Loan[] memory) {}

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {}

    function balanceOf(address account, uint256 id) external view override returns (uint256) {}

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        override
        returns (uint256[] memory)
    {}

    function setApprovalForAll(address operator, bool approved) external override {}

    function isApprovedForAll(address account, address operator) external view override returns (bool) {}

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        override
    {}

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external override {}

    function claim() external override {}

    function issueImpairmentReceipts() external override returns (uint256[] memory) {}
}
