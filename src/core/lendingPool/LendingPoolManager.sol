// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {ILendingPoolManager, LendingPoolDeployment} from "../interfaces/lendingPool/ILendingPoolManager.sol";
import {IPendingPool} from "../interfaces/lendingPool/IPendingPool.sol";
import {ILendingPool} from "../interfaces/lendingPool/ILendingPool.sol";
import "../AssetFunctionsBase.sol";
import {ILendingPoolErrors} from "../interfaces/lendingPool/ILendingPoolErrors.sol";

contract LendingPoolManager is ILendingPoolManager, AssetFunctionsBase, ILendingPoolErrors {
    mapping(address => LendingPoolDeployment) private lendingPools;
    mapping(address => address) public ownLendingPool;

    constructor(address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {}

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
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPools[lendingPool].pendingPool, amount);
        dNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestDeposit(msg.sender, tranche, amount);
    }

    function cancelDepositRequest(address, uint256) external pure {
        revert("0");
    }

    // #### USER WITHDRAWS #### //
    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        returns (uint256 wNftID)
    {
        wNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestWithdrawal(msg.sender, tranche, amount);
    }

    function cancelWithdrawalRequest(address, uint256) external pure {
        revert("0");
    }

    // #### CLEARING #### //
    function acceptDepositRequest(address lendingPool, uint256 dNftID, uint256 amount) external {
        IPendingPool(lendingPools[lendingPool].pendingPool).acceptDepositRequest(dNftID, amount);
    }

    function declineDepositRequest(address, uint256) external pure{
        revert("0");
    }

    function acceptWithdrawalRequest(address, uint256) external pure {
        revert("0");
    }

    // #### POOL DELEGATE #### //
    function borrowLoan(address, uint256) external pure {
        revert("0");
    }

    function repayLoan(address, uint256) external pure {
        revert("0");
    }

    function updateLoanAmount(address, uint256) external pure {
        revert("0");
    }

    function reportLoss(address lendingPool, uint256 amount) external returns (uint256) {
        return ILendingPool(lendingPool).reportLoss(amount);
    }

    // #### PROTOCOL FEES #### //
    function withdrawProtocolFees() external pure {
        revert("0");
    }

    // #### MODIFIERS #### //

    modifier validLendingPool(address lendingPool) {
        if (lendingPools[lendingPool].lendingPool == address(0)) {
            revert InvalidLendingPool(lendingPool);
        }
        _;
    }

    modifier validTranche(address lendingPool, address tranche) {
        bool trancheExists = false;
        for (uint256 i = 0; i < lendingPools[lendingPool].tranches.length; i++) {
            if (lendingPools[lendingPool].tranches[i] == tranche) trancheExists = true;
        }
        if (!trancheExists) {
            revert InvalidTranche(lendingPool, tranche);
        }
        _;
    }
}
