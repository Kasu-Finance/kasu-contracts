// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../AssetFunctionsBase.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/IKasuAllowList.sol";
import "../../shared/access/KasuAccessControllable.sol";
import "../../shared/access/Roles.sol";
import "../../shared/interfaces/IKasuController.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

contract LendingPoolManager is
    ILendingPoolManager,
    AssetFunctionsBase,
    ILendingPoolErrors,
    KasuAccessControllable,
    Initializable
{
    mapping(address => address) public ownLendingPool;

    mapping(address => LendingPoolDeployment) private lendingPools;

    ILendingPoolFactory private lendingPoolFactory;
    IKasuAllowList private kasuAllowList;

    constructor(address underlyingAsset_, IKasuController controller_)
        AssetFunctionsBase(underlyingAsset_)
        KasuAccessControllable(controller_)
    {}

    function initialize(ILendingPoolFactory lendingPoolFactory_, IKasuAllowList kasuAllowList_) public initializer {
        lendingPoolFactory = lendingPoolFactory_;
        kasuAllowList = kasuAllowList_;
    }

    // #### CREATE POOL #### //

    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        onlyRole(ROLE_LENDING_POOL_CREATOR, msg.sender)
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        lendingPoolDeployment = lendingPoolFactory.createPool(createPoolConfig);
        registerLendingPool(lendingPoolDeployment);
    }

    function registerLendingPool(LendingPoolDeployment memory lendingPoolDeployment) internal {
        lendingPools[lendingPoolDeployment.lendingPool] = lendingPoolDeployment;

        ownLendingPool[lendingPoolDeployment.pendingPool] = lendingPoolDeployment.lendingPool;
        for (uint256 i = 0; i < lendingPoolDeployment.tranches.length; ++i) {
            ownLendingPool[lendingPoolDeployment.tranches[i]] = lendingPoolDeployment.lendingPool;
        }
    }

    // #### USER DEPOSITS #### //
    function requestDeposit(address lendingPool, address tranche, uint256 amount)
        external
        validLendingPool(lendingPool)
        validTranche(lendingPool, tranche)
        isUserAllowed(msg.sender)
        returns (uint256 dNftID)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPools[lendingPool].pendingPool, amount);
        dNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestDeposit(msg.sender, tranche, amount);
    }

    function cancelDepositRequest(address lendingPool, uint256 dNftID) external {
        IPendingPool(lendingPools[lendingPool].pendingPool).cancelDepositRequest(msg.sender, dNftID);
    }

    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        returns (uint256 wNftID)
    {
        wNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestWithdrawal(msg.sender, tranche, amount);
    }

    function cancelWithdrawalRequest(address lendingPool, uint256 wNftID) external {
        IPendingPool(lendingPools[lendingPool].pendingPool).cancelWithdrawalRequest(msg.sender, wNftID);
    }

    // #### LENDING POOL LOAN MANAGER #### //
    function borrowLoan(address lendingPool, uint256 amount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).borrowLoan(amount);
    }

    function repayLoan(address lendingPool, uint256 amount, address repaymentAddress)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).repayLoan(amount, repaymentAddress);
    }

    function reportLoss(address lendingPool, uint256 amount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        returns (uint256)
    {
        return ILendingPool(lendingPool).reportLoss(amount);
    }

    function repayLoss(address lendingPool, uint256 lossId, uint256 amount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
    {
        revert("0");
    }

    function depositFirstLossCapital(address lendingPool, uint256 amount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).depositFirstLossCapital(amount);
    }

    function withdrawFirstLossCapital(address lendingPool, uint256 withdrawAmount, address withdrawAddress)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).withdrawFirstLossCapital(withdrawAmount, withdrawAddress);
    }

    // #### LENDING POOL MANAGER #### //

    function forceImmediateWithdrawal(address lendingPool, address tranche, address user, uint256 sharesToWithdraw)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).forceImmediateWithdrawal(tranche, user, sharesToWithdraw);
    }

    function batchForceWithdrawals(address lendingPool, ForceWithdrawalInput[] calldata input)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        returns (uint256[] memory wNftIDs)
    {
        wNftIDs = IPendingPool(ILendingPool(lendingPool).getPendingPool()).batchForceWithdrawals(input);
    }

    function stopLendingPool(address lendingPool, address firstLossCapitalReceiver)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).stop(firstLossCapitalReceiver);
    }

    function forceCancelDepositRequest(address lendingPool, uint256 dNftID)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        revert("0");
    }

    function forceCancelWithdrawalRequest(address lendingPool, uint256 wNftID)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        revert("0");
    }

    // config

    function updateMinimumDepositAmount(address lendingPool, address tranche, uint256 minimumDepositAmount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).updateMinimumDepositAmount(tranche, minimumDepositAmount);
    }

    function updateMaximumDepositAmount(address lendingPool, address tranche, uint256 maximumDepositAmount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).updateMaximumDepositAmount(tranche, maximumDepositAmount);
    }

    function updateTrancheInterestRate(address lendingPool, address tranche, uint256 interestRate)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).updateTrancheInterestRate(tranche, interestRate);
    }

    function updateTrancheDesiredRatios(
        address lendingPool,
        address[] calldata tranches,
        uint256[] calldata desiredRatios
    ) external onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender) {
        ILendingPool(lendingPool).updateTrancheDesiredRatios(tranches, desiredRatios);
    }

    function updateTrancheInterestRateChangeEpochDelay(address lendingPool, address tranche, uint256 epochDelay)
        external
        onlyLendingPoolRole(lendingPool, ROLE_KASU_ADMIN, msg.sender)
    {
        ILendingPool(lendingPool).updateTrancheInterestRateChangeEpochDelay(tranche, epochDelay);
    }

    function updateTotalDesiredLoanAmount(address lendingPool, uint256 amount)
        external
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
    {
        ILendingPool(lendingPool).updateTotalDesiredLoanAmount(amount);
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
        for (uint256 i = 0; i < lendingPools[lendingPool].tranches.length; ++i) {
            if (lendingPools[lendingPool].tranches[i] == tranche) trancheExists = true;
        }
        if (!trancheExists) {
            revert InvalidTranche(lendingPool, tranche);
        }
        _;
    }

    modifier isUserAllowed(address user) {
        if (!kasuAllowList.isAllowed(user)) {
            revert IKasuAllowList.UserNotInAllowList(user);
        }
        _;
    }
}
