// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ILendingPool} from "./ILendingPool.sol";
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
    function registerLendingPool(LendingPoolDeployment calldata lendingPoolDeployment) external;

    // #### USER DEPOSITS #### //
    function requestDeposit(address lendingPool, address tranche, uint256 amount) external returns (uint256 dNftID);

    function cancelDepositRequest(address tranche, uint256 dNftID) external;

    // #### USER WITHDRAWS #### //
    function requestWithdrawal(address tranche, uint256 amount) external returns (uint256 wNftID);

    function cancelWithdrawalRequest(address tranche, uint256 wNftID) external;

    // #### CLEARING #### //
    function acceptDepositRequest(address tranche, uint256 dNftID) external;

    function declineDepositRequest(address tranche, uint256 dNftID) external;

    function acceptWithdrawalRequest(address tranche, uint256 wNftID) external;

    // #### POOL DELEGATE #### //
    function borrowLoan(address lendingPool, uint256 amount) external;

    function repayLoan(address lendingPool, uint256 amount) external;

    function updateLoanAmount(address lendingPool, uint256 amount) external;

    function reportLoss(address lendingPool, uint256 amount) external returns (uint256 lossId);

    // #### PROTOCOL FEES #### //
    function withdrawProtocolFees() external;
}
