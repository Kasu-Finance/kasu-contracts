// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct LendingPoolInfo {
    TrancheData[] tranches;
    address pendingPool;
    uint256 firstLossCapital;
    uint256 totalBalance;
    uint256 excessFunds;
    uint256 excessTargetLiquidity; // percentage of not borrowed funds (only as senior deposits)
}

struct TrancheData {
    address trancheAddress;
    uint256 balance;
    uint256 interestRate;
}

/**
 * @notice Interface for the LendingPool contract.
 * @dev Can only be called by the LendingPoolManager contract.
 */
interface ILendingPool is IERC20 {
    function getPendingPool() external view returns (address);

    // #### CLEARING #### //
    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external;

    // function declineDepositRequest(address tranche, uint256 dNftID) external;

    // function acceptWithdrawalRequest(address tranche, uint256 wNftID) external;

    // #### POOL DELEGATE #### //
    //     function borrowLoan(uint256 amount) external;

    //     function repayLoan(uint256 amount) external;

    //     function updateLoanAmount(uint256 amount) external;

    //     function reportLoss(uint256 amount) external returns (uint256 lossId);

    //     function repayLoss(uint256 lossId, uint256 amount) external;

    //     // #### PROTOCOL FEES #### //
    //     function withdrawProtocolFees() external;
}
