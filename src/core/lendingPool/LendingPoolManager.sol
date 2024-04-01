// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../AssetFunctionsBase.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/IKasuAllowList.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/clearing/IAcceptedRequestsCalculation.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../../shared/access/KasuAccessControllable.sol";
import "../../shared/access/Roles.sol";
import "../../shared/interfaces/IKasuController.sol";

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
    IUserManager private userManager;
    IClearingCoordinator private clearingCoordinator;

    constructor(address underlyingAsset_, IKasuController controller_)
        AssetFunctionsBase(underlyingAsset_)
        KasuAccessControllable(controller_)
    {}

    function initialize(
        ILendingPoolFactory lendingPoolFactory_,
        IKasuAllowList kasuAllowList_,
        IUserManager userManager_,
        IClearingCoordinator clearingCoordinator_
    ) public initializer {
        lendingPoolFactory = lendingPoolFactory_;
        kasuAllowList = kasuAllowList_;
        userManager = userManager_;
        clearingCoordinator = clearingCoordinator_;
    }

    // #### CREATE POOL #### //

    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        whenNotPaused
        onlyRole(ROLE_LENDING_POOL_CREATOR, msg.sender)
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        lendingPoolDeployment = lendingPoolFactory.createPool(createPoolConfig);
        _registerLendingPool(lendingPoolDeployment);
    }

    function _registerLendingPool(LendingPoolDeployment memory lendingPoolDeployment) internal {
        lendingPools[lendingPoolDeployment.lendingPool] = lendingPoolDeployment;
        clearingCoordinator.initializeLendingPool(lendingPoolDeployment.lendingPool);
    }

    // #### USER DEPOSITS #### //
    function requestDeposit(address lendingPool, address tranche, uint256 amount)
        external
        whenNotPaused
        validLendingPool(lendingPool)
        isUserNotBlocked(msg.sender)
        isUserAllowed(msg.sender)
        returns (uint256 dNftID)
    {
        return _requestDeposit(lendingPool, tranche, amount);
    }

    function requestDepositWithKyc(
        address lendingPool,
        address tranche,
        uint256 amount,
        uint256 blockExpiration,
        bytes calldata signature
    )
        external
        whenNotPaused
        validLendingPool(lendingPool)
        isUserNotBlocked(msg.sender)
        isUserKycd(msg.sender, blockExpiration, signature)
        returns (uint256 dNftID)
    {
        return _requestDeposit(lendingPool, tranche, amount);
    }

    function _requestDeposit(address lendingPool, address tranche, uint256 amount) internal returns (uint256 dNftID) {
        // TODO: more than 0
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPools[lendingPool].pendingPool, amount);
        // notify user manager to be able to calculate loyalty levels
        userManager.userRequestedDeposit(msg.sender, lendingPool);
        dNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestDeposit(msg.sender, tranche, amount);
    }

    function cancelDepositRequest(address lendingPool, uint256 dNftID)
        external
        whenNotPaused
        validLendingPool(lendingPool)
    {
        IPendingPool(lendingPools[lendingPool].pendingPool).cancelDepositRequest(msg.sender, dNftID);
    }

    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        whenNotPaused
        validLendingPool(lendingPool)
        returns (uint256 wNftID)
    {
        // TODO: more than 0
        wNftID = IPendingPool(lendingPools[lendingPool].pendingPool).requestWithdrawal(msg.sender, tranche, amount);
    }

    function cancelWithdrawalRequest(address lendingPool, uint256 wNftID)
        external
        whenNotPaused
        validLendingPool(lendingPool)
    {
        IPendingPool(lendingPools[lendingPool].pendingPool).cancelWithdrawalRequest(msg.sender, wNftID);
    }

    /**
     * @notice Claim repaid loss from the lending pool tranche
     * @param lendingPool Address of the lending pool
     * @param tranche Address of the tranche
     * @param lossId ID of the loss
     */
    function claimRepaidLoss(address lendingPool, address tranche, uint256 lossId)
        external
        whenNotPaused
        validLendingPool(lendingPool)
        returns (uint256 claimedAmount)
    {
        claimedAmount = ILendingPool(lendingPool).claimRepaidLoss(msg.sender, tranche, lossId);
    }

    // #### LENDING POOL LOAN MANAGER #### //
    function drawFundsImmediate(address lendingPool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).drawFundsImmediate(amount);
    }

    /**
     * @notice Report loss to the lending pool.
     * @param lendingPool Address of the lending pool.
     * @param amount Amount of loss.
     * @param doMintLossTokens Whether to mint loss tokens to all the users.
     * @return lossId ID of the lending pool loss.
     */
    function reportLoss(address lendingPool, uint256 amount, bool doMintLossTokens)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
        returns (uint256 lossId)
    {
        return ILendingPool(lendingPool).reportLoss(amount, doMintLossTokens);
    }

    function withdrawFirstLossCapital(address lendingPool, uint256 withdrawAmount, address withdrawAddress)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).withdrawFirstLossCapital(withdrawAmount, withdrawAddress);
    }

    function updateTargetExcessLiquidityPercentage(address lendingPool, uint256 targetExcessLiquidityPercentage)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTargetExcessLiquidityPercentage(targetExcessLiquidityPercentage);
    }

    function updateMinimumExcessLiquidityPercentage(address lendingPool, uint256 minumumExcessLiquidityPercentage)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMinimumExcessLiquidityPercentage(minumumExcessLiquidityPercentage);
    }

    // TODO: Pool Repayer role
    function depositFirstLossCapital(address lendingPool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).depositFirstLossCapital(amount);
    }

    // TODO: Pool Repayer role
    function repayLoan(address lendingPool, uint256 amount, address repaymentAddress)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).repayLoan(amount, repaymentAddress);
    }

    // #### LENDING POOL BORROWER #### //

    /**
     * @notice Repay loss to the lending pool.
     * @param lendingPool Address of the lending pool.
     * @param tranche Address of the tranche to repay to.
     * @param lossId ID of the loss.
     * @param amount Amount to repay.
     */
    function repayLoss(address lendingPool, address tranche, uint256 lossId, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_BORROWER, msg.sender)
        validLendingPool(lendingPool)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).repayLoss(tranche, lossId, amount);
    }

    // #### LENDING POOL MANAGER #### //

    function updateDrawRecipient(address lendingPool, address drawRecipient)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateDrawRecipient(drawRecipient);
    }

    function forceImmediateWithdrawal(address lendingPool, address tranche, address user, uint256 sharesToWithdraw)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).forceImmediateWithdrawal(tranche, user, sharesToWithdraw);
    }

    function batchForceWithdrawals(address lendingPool, ForceWithdrawalInput[] calldata input)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
        returns (uint256[] memory wNftIDs)
    {
        wNftIDs = IPendingPool(ILendingPool(lendingPool).getPendingPool()).batchForceWithdrawals(input);
    }

    function stopLendingPool(address lendingPool, address firstLossCapitalReceiver)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).stop(firstLossCapitalReceiver);
    }

    function forceCancelDepositRequest(address lendingPool, uint256 dNftID)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        IPendingPool pendingPool = IPendingPool(lendingPools[lendingPool].pendingPool);
        address dNftOwner = pendingPool.ownerOf(dNftID);
        pendingPool.cancelDepositRequest(dNftOwner, dNftID);
    }

    function forceCancelWithdrawalRequest(address lendingPool, uint256 wNftID)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        IPendingPool pendingPool = IPendingPool(lendingPools[lendingPool].pendingPool);
        address wNftOwner = pendingPool.ownerOf(wNftID);
        pendingPool.cancelDepositRequest(wNftOwner, wNftID);
    }

    // clearing
    // TODO: access control
    function registerClearingConfig(address lendingPool, uint256 epoch, ClearingConfiguration calldata clearingConfig)
        external
        whenNotPaused
    {
        clearingCoordinator.registerClearingConfig(lendingPool, epoch, clearingConfig);
    }

    // TODO: access control
    function doClearing(
        address lendingPool,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize
    ) external whenNotPaused {
        clearingCoordinator.doClearing(
            lendingPool, targetEpoch, pendingRequestsPriorityCalculationBatchSize, acceptedRequestsExecutionBatchSize
        );
    }

    // config

    function updateMinimumDepositAmount(address lendingPool, address tranche, uint256 minimumDepositAmount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMinimumDepositAmount(tranche, minimumDepositAmount);
    }

    function updateMaximumDepositAmount(address lendingPool, address tranche, uint256 maximumDepositAmount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMaximumDepositAmount(tranche, maximumDepositAmount);
    }

    function updateTrancheInterestRate(address lendingPool, address tranche, uint256 interestRate)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheInterestRate(tranche, interestRate);
    }

    function updateTrancheDesiredRatios(address lendingPool, uint256[] calldata desiredRatios)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheDesiredRatios(desiredRatios);
    }

    function updateTrancheInterestRateChangeEpochDelay(address lendingPool, uint256 epochDelay)
        external
        whenNotPaused
        onlyRole(ROLE_KASU_ADMIN, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheInterestRateChangeEpochDelay(epochDelay);
    }

    function updateDesiredDrawAmount(address lendingPool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_LENDING_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateDesiredDrawAmount(amount);
    }

    function _validLendingPool(address lendingPool) internal view {
        if (lendingPools[lendingPool].lendingPool == address(0)) {
            revert InvalidLendingPool(lendingPool);
        }
    }

    // #### MODIFIERS #### //

    modifier validLendingPool(address lendingPool) {
        _validLendingPool(lendingPool);
        _;
    }

    modifier isUserNotBlocked(address user) {
        if (kasuAllowList.blockList(user)) {
            revert IKasuAllowList.UserBlocked(user);
        }
        _;
    }

    modifier isUserAllowed(address user) {
        if (!kasuAllowList.allowList(user)) {
            revert IKasuAllowList.UserNotInAllowList(user);
        }
        _;
    }

    modifier isUserKycd(address user, uint256 blockExpiration, bytes calldata signature) {
        if (!kasuAllowList.verifyUserKyc(user, blockExpiration, signature)) {
            revert IKasuAllowList.UserNotKycd(user);
        }
        _;
    }
}
