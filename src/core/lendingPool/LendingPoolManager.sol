// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/lendingPool/ILendingPoolManager.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/IKasuAllowList.sol";
import "../interfaces/IUserManager.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../../shared/interfaces/IKasuController.sol";
import "../../shared/access/KasuAccessControllable.sol";
import "../../shared/access/Roles.sol";
import "../AssetFunctionsBase.sol";
import "../DepositSwap.sol";
import "../../shared/AddressLib.sol";

/**
 * @title Lending Pool Manager Contract
 * @notice This contract is used as an entry point for all the lending pool interactions.
 */
contract LendingPoolManager is
    ILendingPoolManager,
    DepositSwap,
    AssetFunctionsBase,
    ILendingPoolErrors,
    KasuAccessControllable,
    Initializable
{
    /// @notice Lending pool factory contract.
    ILendingPoolFactory private _lendingPoolFactory;
    /// @notice Kasu allow list contract.
    IKasuAllowList private _kasuAllowList;
    /// @notice User manager contract.
    IUserManager private _userManager;
    /// @notice Clearing coordinator contract.
    IClearingCoordinator private _clearingCoordinator;

    /// @notice Lending pool deployment addresses.
    mapping(address => LendingPoolDeployment) public lendingPools;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param underlyingAsset_ Underlying asset contract address.
     * @param controller_ Kasu controller contract.
     * @param weth_ WETH contract.
     * @param swapper_ Swapper contract.
     */
    constructor(address underlyingAsset_, IKasuController controller_, IWETH9 weth_, ISwapper swapper_)
        DepositSwap(weth_, swapper_)
        AssetFunctionsBase(underlyingAsset_)
        KasuAccessControllable(controller_)
    {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract.
     * @param lendingPoolFactory_ Lending pool factory contract.
     * @param kasuAllowList_ Kasu allow list contract.
     * @param userManager_ User manager contract.
     * @param clearingCoordinator_ Clearing coordinator contract.
     */
    function initialize(
        ILendingPoolFactory lendingPoolFactory_,
        IKasuAllowList kasuAllowList_,
        IUserManager userManager_,
        IClearingCoordinator clearingCoordinator_
    ) public initializer {
        AddressLib.checkIfZero(address(lendingPoolFactory_));
        AddressLib.checkIfZero(address(kasuAllowList_));
        AddressLib.checkIfZero(address(userManager_));
        AddressLib.checkIfZero(address(clearingCoordinator_));

        _lendingPoolFactory = lendingPoolFactory_;
        _kasuAllowList = kasuAllowList_;
        _userManager = userManager_;
        _clearingCoordinator = clearingCoordinator_;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Checks if an address is the lending pool.
     * @param lendingPool Address of the lending pool.
     * @return Whether the address is the lending pool.
     */
    function isLendingPool(address lendingPool) external view returns (bool) {
        return lendingPools[lendingPool].lendingPool != address(0);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // #### USER #### //

    /**
     * @notice Request deposit to the lending pool tranche.
     * @dev User should not be blocked to deposit.
     * User should be on the allowlist to deposit.
     * @param lendingPool Address of the lending pool to deposit to.
     * @param tranche Address of the tranche to deposit to.
     * @param maxAmount Maximum amount to deposit. If no swap data is provided, this amount will be deposited.
     * @param swapData Swap data for deposit. Ignore if empty.
     * @return dNftID ID of the deposit NFT.
     */
    function requestDeposit(address lendingPool, address tranche, uint256 maxAmount, bytes calldata swapData)
        external
        payable
        whenNotPaused
        validLendingPool(lendingPool)
        isUserNotBlocked(msg.sender)
        isUserAllowed(msg.sender)
        returns (uint256 dNftID)
    {
        return _requestDeposit(lendingPool, tranche, maxAmount, swapData);
    }

    /**
     * @notice Request deposit to the lending pool tranche with user KYC.
     * @dev User should not be blocked to deposit.
     * User should be KYC'd to deposit.
     * @param lendingPool Address of the lending pool to deposit to.
     * @param tranche Address of the tranche to deposit to.
     * @param maxAmount Maximum amount to deposit. If no swap data is provided, this amount will be deposited.
     * @param swapData Swap data for deposit. Ignore if empty.
     * @param blockExpiration Expiration block number for the KYC signature.
     * @param signature KYC signature.
     * @return dNftID ID of the deposit NFT.
     */
    function requestDepositWithKyc(
        address lendingPool,
        address tranche,
        uint256 maxAmount,
        bytes calldata swapData,
        uint256 blockExpiration,
        bytes calldata signature
    )
        external
        payable
        whenNotPaused
        validLendingPool(lendingPool)
        isUserNotBlocked(msg.sender)
        isUserKycd(msg.sender, blockExpiration, signature)
        returns (uint256 dNftID)
    {
        return _requestDeposit(lendingPool, tranche, maxAmount, swapData);
    }

    /**
     * @notice Cancel deposit request.
     * @param lendingPool Address of the lending pool.
     * @param dNftID ID of the deposit NFT to cancel.
     */
    function cancelDepositRequest(address lendingPool, uint256 dNftID)
        external
        whenNotPaused
        validLendingPool(lendingPool)
    {
        _pendingPool(lendingPool).cancelDepositRequest(msg.sender, dNftID);
    }

    /**
     * @notice Request withdrawal from the lending pool tranche.
     * @param lendingPool Address of the lending pool to withdraw from.
     * @param tranche Address of the tranche to withdraw from.
     * @param amount Amount of tranche shares to withdraw.
     * @return wNftID ID of the withdrawal NFT.
     */
    function requestWithdrawal(address lendingPool, address tranche, uint256 amount)
        external
        whenNotPaused
        validLendingPool(lendingPool)
        returns (uint256 wNftID)
    {
        wNftID = _pendingPool(lendingPool).requestWithdrawal(msg.sender, tranche, amount);
    }

    /**
     * @notice Cancel withdrawal request.
     * @param lendingPool Address of the lending pool.
     * @param wNftID ID of the withdrawal NFT to cancel.
     */
    function cancelWithdrawalRequest(address lendingPool, uint256 wNftID)
        external
        whenNotPaused
        validLendingPool(lendingPool)
    {
        _pendingPool(lendingPool).cancelWithdrawalRequest(msg.sender, wNftID);
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

    // #### LENDING POOL CREATOR #### //

    /**
     * @notice Creates a new lending pool.
     * @param createPoolConfig Configuration for creating a lending pool.
     * @return lendingPoolDeployment Deployment addresses of the lending pool.
     */
    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        whenNotPaused
        onlyRole(ROLE_LENDING_POOL_CREATOR, msg.sender)
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        lendingPoolDeployment = _lendingPoolFactory.createPool(createPoolConfig);
        _registerLendingPool(lendingPoolDeployment);
    }

    function _registerLendingPool(LendingPoolDeployment memory lendingPoolDeployment) internal {
        lendingPools[lendingPoolDeployment.lendingPool] = lendingPoolDeployment;
        _clearingCoordinator.initializeLendingPool(lendingPoolDeployment.lendingPool);
    }

    // #### POOL ADMIN #### //

    /**
     * @notice Update draw recipient address.
     * @param lendingPool Address of the lending pool.
     * @param drawRecipient Address of the draw recipient.
     */
    function updateDrawRecipient(address lendingPool, address drawRecipient)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_ADMIN, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateDrawRecipient(drawRecipient);
    }

    // #### POOL FUNDS MANAGER #### //

    /**
     * @notice Report unrealized loss to the lending pool.
     * @param lendingPool Address of the lending pool to report loss to.
     * @param amount Reported loss amount.
     * @param doMintLossTokens Whether to mint loss tokens to all the users in this transaction.
     * @return lossId ID of the reported lending pool loss.
     */
    function reportLoss(address lendingPool, uint256 amount, bool doMintLossTokens)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
        validLendingPool(lendingPool)
        returns (uint256 lossId)
    {
        return ILendingPool(lendingPool).reportLoss(amount, doMintLossTokens);
    }

    /**
     * @notice Repay owed funds to the lending pool.
     * @param lendingPool Address of the lending pool.
     * @param amount Amount to repay.
     * @param repaymentAddress Address to repay from.
     */
    function repayOwedFunds(address lendingPool, uint256 amount, address repaymentAddress)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        _transferAssetsFrom(repaymentAddress, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).repayOwedFunds(amount);
    }

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
        onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).repayLoss(tranche, lossId, amount);
    }

    /**
     * @notice Deposit first loss capital to the lending pool.
     * @param lendingPool Address of the lending pool.
     * @param amount Amount to deposit.
     */
    function depositFirstLossCapital(address lendingPool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(lendingPool, amount);
        ILendingPool(lendingPool).depositFirstLossCapital(amount);
    }

    /**
     * @notice Withdraw first loss capital from the lending pool.
     * @dev The pool should be stopped before withdrawing first loss capital.
     * @param lendingPool Address of the lending pool.
     * @param withdrawAmount Amount to withdraw.
     * @param withdrawAddress Address to withdraw assets to.
     */
    function withdrawFirstLossCapital(address lendingPool, uint256 withdrawAmount, address withdrawAddress)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).withdrawFirstLossCapital(withdrawAmount, withdrawAddress);
    }

    // #### POOL CLEARING MANAGER #### //

    /**
     * @notice Execute clearing for the lending pool.
     * @dev Can possibly be executed in multiple transactions.
     * @param lendingPool Address of the lending pool.
     * @param targetEpoch Target epoch to clear.
     * @param priorityCalculationBatchSize Numbers of user requests to process in step 2 of the clearing process.
     * @param acceptRequestsBatchSize Numbers of user requests to process in step 4 of the clearing process.
     * @param clearingConfigOverride Clearing configuration override. Ignore if isConfigOverridden is false. Only applied when step 3 is executed.
     * @param isConfigOverridden Whether the clearing configuration is overridden.
     */
    function doClearing(
        address lendingPool,
        uint256 targetEpoch,
        uint256 priorityCalculationBatchSize,
        uint256 acceptRequestsBatchSize,
        ClearingConfiguration calldata clearingConfigOverride,
        bool isConfigOverridden
    )
        external
        whenNotPaused
        validLendingPool(lendingPool)
        onlyLendingPoolRole(lendingPool, ROLE_POOL_CLEARING_MANAGER, msg.sender)
    {
        _clearingCoordinator.doClearing(
            lendingPool,
            targetEpoch,
            priorityCalculationBatchSize,
            acceptRequestsBatchSize,
            clearingConfigOverride,
            isConfigOverridden
        );
    }

    // #### POOL MANAGER #### //

    /**
     * @notice Force immediate withdrawal for user from the lending pool tranche by the pool manager.
     * @dev Can only be called by the pool manager.
     * User tranche shares are immediately withdrawn and assets are transferred to the user.
     * Will fail if the lending pool doesn't have enough assets to return.
     * @param lendingPool Address of the lending pool.
     * @param tranche Address of the tranche.
     * @param user Address of the user to withdraw for.
     * @param sharesToWithdraw Amount of tranche shares to withdraw.
     * @return assetAmount Amount of assets withdrawn.
     */
    function forceImmediateWithdrawal(address lendingPool, address tranche, address user, uint256 sharesToWithdraw)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
        returns (uint256)
    {
        return ILendingPool(lendingPool).forceImmediateWithdrawal(tranche, user, sharesToWithdraw);
    }

    /**
     * @notice Force withdrawals for multiple users from the lending pool by the pool manager.
     * @dev Can only be called by the pool manager.
     * Same as normal withdrawal but cannot be canceled by the user.
     * Forced withdrawal has the highest priority (above highest standard priority) when clearing.
     * @param lendingPool Address of the lending pool.
     * @param input Array of force withdrawal details.
     */
    function batchForceWithdrawals(address lendingPool, ForceWithdrawalInput[] calldata input)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
        returns (uint256[] memory wNftIDs)
    {
        wNftIDs = _pendingPool(lendingPool).batchForceWithdrawals(input);
    }

    /**
     * @notice Force cancel deposit request for the user by the pool manager.
     * @param lendingPool Address of the lending pool.
     * @param dNftID ID of the deposit NFT to cancel.
     */
    function forceCancelDepositRequest(address lendingPool, uint256 dNftID)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        IPendingPool pendingPool = _pendingPool(lendingPool);
        address dNftOwner = pendingPool.ownerOf(dNftID);
        pendingPool.cancelDepositRequest(dNftOwner, dNftID);
    }

    /**
     * @notice Force cancel withdrawal request for the user by the pool manager.
     * @dev Can cancel forced withdrawal requests.
     * @param lendingPool Address of the lending pool.
     * @param wNftID ID of the withdrawal NFT to cancel.
     */
    function forceCancelWithdrawalRequest(address lendingPool, uint256 wNftID)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        _pendingPool(lendingPool).forceCancelWithdrawalRequest(wNftID);
    }

    /**
     * @notice Stop lending pool.
     * @dev Pool Funds Manager must first repay all owed funds before the pool can be stopped.
     * @param lendingPool Address of the lending pool.
     */
    function stopLendingPool(address lendingPool)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).stop();
    }

    // #### CONFIG #### //

    /**
     * @notice Update target excess liquidity percentage.
     * @param lendingPool Address of the lending pool.
     * @param targetExcessLiquidityPercentage New target excess liquidity percentage. 100% is 10^5.
     */
    function updateTargetExcessLiquidityPercentage(address lendingPool, uint256 targetExcessLiquidityPercentage)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTargetExcessLiquidityPercentage(targetExcessLiquidityPercentage);
    }

    /**
     * @notice Update minimum excess liquidity percentage.
     * @param lendingPool Address of the lending pool.
     * @param minimumExcessLiquidityPercentage New minimum excess liquidity percentage. 100% is 10^5.
     */
    function updateMinimumExcessLiquidityPercentage(address lendingPool, uint256 minimumExcessLiquidityPercentage)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMinimumExcessLiquidityPercentage(minimumExcessLiquidityPercentage);
    }

    /**
     * @notice Update minimum deposit amount for the lending pool tranche.
     * @dev Can't be more than the maximum deposit amount.
     * @param lendingPool Address of the lending pool.
     * @param tranche Address of the tranche.
     * @param minimumDepositAmount New minimum deposit amount for the tranche.
     */
    function updateMinimumDepositAmount(address lendingPool, address tranche, uint256 minimumDepositAmount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMinimumDepositAmount(tranche, minimumDepositAmount);
    }

    /**
     * @notice Update maximum deposit amount for the lending pool tranche.
     * @dev Can't be less than the minimum deposit amount.
     * @param lendingPool Address of the lending pool.
     * @param tranche Address of the tranche.
     * @param maximumDepositAmount New maximum deposit amount for the tranche.
     */
    function updateMaximumDepositAmount(address lendingPool, address tranche, uint256 maximumDepositAmount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateMaximumDepositAmount(tranche, maximumDepositAmount);
    }

    /**
     * @notice Update tranche interest rate per epoch for the lending pool.
     * @dev Interest rate update has a delay measured in epochs. This delay is set in the lending pool.
     * @param lendingPool Address of the lending pool.
     * @param tranche Address of the tranche.
     * @param interestRate New interest rate per epoch for the tranche. 100% is 10^18.
     */
    function updateTrancheInterestRate(address lendingPool, address tranche, uint256 interestRate)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheInterestRate(tranche, interestRate);
    }

    /**
     * @notice Update tranche desired ratios for the lending pool.
     * @dev Desired ratios are in the same order as the tranches.
     * The length of the desired ratios array must be equal to the number of tranches.
     * The sum of the desired ratios must be 100%.
     * @param lendingPool Address of the lending pool.
     * @param desiredRatios New desired ratios for the tranches. 100% is 10^5.
     */
    function updateTrancheDesiredRatios(address lendingPool, uint256[] calldata desiredRatios)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheDesiredRatios(desiredRatios);
    }

    /**
     * @notice Update desired draw amount for the lending pool for the next time clearing is executed.
     * @dev Lending pool desired draw amount is decreased every time a draw is executed.
     * @param lendingPool Address of the lending pool.
     * @param amount New desired draw amount.
     */
    function updateDesiredDrawAmount(address lendingPool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateDesiredDrawAmount(amount);
    }

    /**
     * @notice Update tranche interest rate change epoch delay for the lending pool.
     * @dev Only Kasu admin can call this function.
     * @param lendingPool Address of the lending pool.
     * @param epochDelay New tranche interest rate change delay in epochs.
     */
    function updateTrancheInterestRateChangeEpochDelay(address lendingPool, uint256 epochDelay)
        external
        whenNotPaused
        onlyRole(ROLE_KASU_ADMIN, msg.sender)
        validLendingPool(lendingPool)
    {
        ILendingPool(lendingPool).updateTrancheInterestRateChangeEpochDelay(epochDelay);
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _pendingPool(address lendingPool) private view returns (IPendingPool) {
        return IPendingPool(lendingPools[lendingPool].pendingPool);
    }

    function _validLendingPool(address lendingPool) private view {
        if (lendingPools[lendingPool].lendingPool == address(0)) {
            revert InvalidLendingPool(lendingPool);
        }
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _requestDeposit(address lendingPool, address tranche, uint256 maxAmount, bytes calldata swapData)
        internal
        returns (uint256 dNftID)
    {
        uint256 amount;
        address[] memory swapTokens;
        if (swapData.length > 0) {
            SwapDepositBag memory swapBag = abi.decode(swapData, (SwapDepositBag));
            swapTokens = swapBag.inTokens;
            uint256 swappedAmount = _transferAndSwap(swapBag, address(_underlyingAsset));
            amount = Math.min(swappedAmount, maxAmount);
        } else {
            amount = maxAmount;
            _transferAssetsFrom(msg.sender, address(this), amount);
        }

        _approveAsset(lendingPools[lendingPool].pendingPool, amount);
        // notify user manager to be able to calculate loyalty levels
        _userManager.userRequestedDeposit(msg.sender, lendingPool);
        dNftID = _pendingPool(lendingPool).requestDeposit(msg.sender, tranche, amount);

        if (swapTokens.length > 0 || msg.value > 0) {
            _postSwap(swapTokens, address(_underlyingAsset));
        }
    }

    /* ========== MODIFIERS ========== */

    modifier validLendingPool(address lendingPool) {
        _validLendingPool(lendingPool);
        _;
    }

    modifier isUserNotBlocked(address user) {
        if (_kasuAllowList.blockList(user)) {
            revert IKasuAllowList.UserBlocked(user);
        }
        _;
    }

    modifier isUserAllowed(address user) {
        if (!_kasuAllowList.allowList(user)) {
            revert IKasuAllowList.UserNotInAllowList(user);
        }
        _;
    }

    modifier isUserKycd(address user, uint256 blockExpiration, bytes calldata signature) {
        if (!_kasuAllowList.verifyUserKyc(user, blockExpiration, signature)) {
            revert IKasuAllowList.UserNotKycd(user);
        }
        _;
    }
}
