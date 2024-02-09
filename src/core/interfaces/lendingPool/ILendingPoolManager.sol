// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./IPendingPool.sol";
import "./ILendingPoolFactory.sol";

struct ForceWithdrawalDetails {
    address user;
    address tranche;
    uint256 amount;
}

struct ForceWithdrawalResult {
    address user;
    uint256 wNftID;
}

interface ILendingPoolManager {
    function createPool(PoolConfiguration calldata poolConfiguration)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment);

    function ownLendingPool(address contractAddress) external view returns (address lendingPool);

    // #### USER #### //
    function requestDeposit(address lendingPool, address tranche, uint256 amount) external returns (uint256 dNftID);

    function cancelDepositRequest(address lendingPool, uint256 dNftID) external;

    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        returns (uint256 wNftID);

    function cancelWithdrawalRequest(address lendingPool, uint256 wNftID) external;

    // #### POOL DELEGATE #### //
    function borrowLoan(address lendingPool, uint256 amount) external;

    function repayLoan(address lendingPool, uint256 amount, address repaymentAddress) external;

    function updateLoanAmount(address lendingPool, uint256 amount) external;

    function reportLoss(address lendingPool, uint256 amount) external returns (uint256 lossId);

    function depositFirstLossCapital(address lendingPool, uint256 amount) external;

    function withdrawFirstLossCapital(address lendingPool, uint256 withdrawAmount, address withdrawAddress) external;

    function forceImmediateWithdrawal(address lendingPool, address tranche, address user, uint256 sharesToWithdraw)
        external;

    function batchForceWithdrawals(address lendingPool, ForceWithdrawalInput[] calldata input)
        external
        returns (uint256[] memory);

    function stopLendingPool(address lendingPool, address firstLossCapitalReceiver) external;

    // #### PROTOCOL FEES #### //
    function withdrawProtocolFees() external;
}
