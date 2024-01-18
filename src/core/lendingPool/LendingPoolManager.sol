// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ILendingPoolManager, LendingPoolDeployment} from "../interfaces/lendingPool/ILendingPoolManager.sol";
import {IPendingPool} from "../interfaces/lendingPool/IPendingPool.sol";

contract LendingPoolManager is ILendingPoolManager {
    mapping(address => LendingPoolDeployment) private lendingPools;
    mapping(address => address) public ownLendingPool;

    function registerLendingPool(LendingPoolDeployment calldata lendingPoolDeployment) external {
        lendingPools[lendingPoolDeployment.lendingPool] = lendingPoolDeployment;

        ownLendingPool[lendingPoolDeployment.pendingPool] = lendingPoolDeployment.lendingPool;
        for (uint256 i = 0; i < lendingPoolDeployment.tranches.length; i++) {
            ownLendingPool[lendingPoolDeployment.tranches[i]] = lendingPoolDeployment.lendingPool;
        }
    }

    // #### USER DEPOSITS #### //
    function requestDeposit(address lendingPool, address tranche, uint256 amount)
        external
        validLendingPool(lendingPool)
        validTranche(lendingPool, tranche)
        returns (uint256 dNftID)
    {
        // TODO: transfer user deposit funds
        dNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestDeposit(msg.sender, tranche, amount);
    }

    function cancelDepositRequest(address tranche, uint256 dNftID) external {
        revert("0");
    }

    // #### USER WITHDRAWS #### //
    function requestWithdrawal(address tranche, uint256 amount) external returns (uint256 wNftID) {
        revert("0");
    }

    function cancelWithdrawalRequest(address tranche, uint256 wNftID) external {
        revert("0");
    }

    // #### CLEARING #### //
    function acceptDepositRequest(address tranche, uint256 dNftID) external {
        revert("0");
    }

    function declineDepositRequest(address tranche, uint256 dNftID) external {
        revert("0");
    }

    function acceptWithdrawalRequest(address tranche, uint256 wNftID) external {
        revert("0");
    }

    // #### POOL DELEGATE #### //
    function borrowLoan(address lendingPool, uint256 amount) external {
        revert("0");
    }

    function repayLoan(address lendingPool, uint256 amount) external {
        revert("0");
    }

    function updateLoanAmount(address lendingPool, uint256 amount) external {
        revert("0");
    }

    function reportLoss(address lendingPool, uint256 amount) external returns (uint256 lossId) {
        revert("0");
    }

    // #### PROTOCOL FEES #### //
    function withdrawProtocolFees() external {
        revert("0");
    }

    modifier validLendingPool(address lendingPool) {
        // TODO: check if lending pool is valid
        _;
    }

    modifier validTranche(address lendingPool, address tranche) {
        // TODO: check if the tranche addrees is valid
        _;
    }
}
