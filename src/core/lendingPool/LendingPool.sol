// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/IFixedTermDeposit.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../interfaces/ISystemVariables.sol";
import "../interfaces/IFeeManager.sol";
import "./LendingPoolStoppable.sol";
import "../AssetFunctionsBase.sol";
import "../Constants.sol";
import "../../shared/AddressLib.sol";
import "../../shared/CommonErrors.sol";

/**
 * @notice Contains tranche interest rate information for the future epochs.
 * @custom:member epoch The epoch number for which the interest rate is set.
 * @custom:member interestRate The interest rate for the epoch.
 */
struct FutureTrancheInterestRates {
    uint256 epoch;
    uint256 interestRate;
}

/**
 * @title LendingPool contract
 * @notice This contract is the ledger of the lending pool balances.
 * @dev The lending pool is also a ERC20 token. This token always represents
 * the total balance of the lending pool against the underlying asset.
 * These ERC20 tokens represent an IOU for the asset.
 * Tokens should only be held by the lending pool tranches and the lending pool itself.
 * Balance of each tranche represents its asset value.
 * Tokens held by the lending pool represent the first loss capital asset value.
 * When interests are applied, the lending pool mints additional tokens to the tranches.
 * When a loss is reported, the lending pool burns tokens from itself and the tranches.
 * New deposits mint new tokens to the tranches.
 * Withdrawals burn tokens from the tranches and the lending pool and transfer asset of the same amount back to the user.
 */
contract LendingPool is ILendingPool, ERC20Upgradeable, AssetFunctionsBase, ILendingPoolErrors, LendingPoolStoppable {
    /// @notice System variables contract.
    ISystemVariables private immutable _systemVariables;
    /// @notice Lending pool manager address.
    address private immutable _lendingPoolManager;
    /// @notice Clearing coordinator contract.
    IClearingCoordinator private immutable _clearingCoordinator;
    /// @notice Fee manager contract.
    IFeeManager private immutable _feeManager;
    /// @dev Fixed term deposit contract.
    IFixedTermDeposit private immutable _fixedTermDeposit;

    /// @notice Lending pool info contains pending pool and tranche addresses.
    LendingPoolInfo private _lendingPoolInfo;
    /// @notice Lending pool configuration.
    PoolConfiguration private _poolConfiguration;
    /// @notice The index of lending pool info and pool configuration
    mapping(address tranche => uint256 index) private _trancheIndex;

    /// @notice Future epoch tranche interest rates.
    /// @dev The array should always have at least one element after initialization.
    mapping(address tranche => FutureTrancheInterestRates[]) private _futureTrancheInterests;
    /// @notice Current tranche interest index.
    mapping(address tranche => uint256) private _trancheInterestIndex;

    /// @notice The fees owed amount in asset that still needs to be repaid.
    uint256 public feesOwedAmount;
    /// @notice Owed amount in asset that still needs to be repaid.
    uint256 public userOwedAmount;

    /// @notice First loss capital amount.
    uint256 public firstLossCapital;
    /// @notice The id of the next reported loss.
    uint256 public nextLossId;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param systemVariables_ System variables contract.
     * @param lendingPoolManager_ Lending pool manager address.
     * @param clearingCoordinator_ Clearing coordinator contract.
     * @param feeManager_ Fee manager contract.
     * @param underlyingAsset_ Underlying asset address.
     */
    constructor(
        ISystemVariables systemVariables_,
        address lendingPoolManager_,
        IClearingCoordinator clearingCoordinator_,
        IFeeManager feeManager_,
        IFixedTermDeposit fixedTermDeposit_,
        address underlyingAsset_
    ) AssetFunctionsBase(underlyingAsset_) {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(lendingPoolManager_);
        AddressLib.checkIfZero(address(clearingCoordinator_));
        AddressLib.checkIfZero(address(feeManager_));
        AddressLib.checkIfZero(address(fixedTermDeposit_));

        _systemVariables = systemVariables_;
        _lendingPoolManager = lendingPoolManager_;
        _clearingCoordinator = clearingCoordinator_;
        _feeManager = feeManager_;
        _fixedTermDeposit = fixedTermDeposit_;

        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the lending pool.
     * @param createPoolConfig Create lending pool configuration.
     * @param lendingPoolInfo_ Lending pool info containing other addresses and configuration.
     */
    function initialize(CreatePoolConfig calldata createPoolConfig, LendingPoolInfo calldata lendingPoolInfo_)
        public
        initializer
        returns (PoolConfiguration memory)
    {
        AddressLib.checkIfZero(lendingPoolInfo_.pendingPool);

        __ERC20_init(createPoolConfig.poolName, createPoolConfig.poolSymbol);

        _lendingPoolInfo = lendingPoolInfo_;

        // setup pool configuration
        _updateTargetExcessLiquidityPercentage(createPoolConfig.targetExcessLiquidityPercentage);
        _updateMinimumExcessLiquidityPercentage(createPoolConfig.minExcessLiquidityPercentage);
        _updateDrawRecipient(createPoolConfig.drawRecipient);
        _updateTrancheInterestRateChangeEpochDelay(_systemVariables.defaultTrancheInterestChangeEpochDelay());
        _updateDesiredDrawAmount(createPoolConfig.desiredDrawAmount);

        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            TrancheConfig memory trancheConfig;
            _poolConfiguration.tranches.push(trancheConfig);

            _setTrancheIndex(lendingPoolInfo_.trancheAddresses[i], i);

            _updateMaximumTrancheDepositAmount(
                lendingPoolInfo_.trancheAddresses[i], createPoolConfig.tranches[i].maxDepositAmount
            );
            _updateMinimumTrancheDepositAmount(
                lendingPoolInfo_.trancheAddresses[i], createPoolConfig.tranches[i].minDepositAmount
            );

            // set tranche interest rate
            _verifyTrancheInterestRate(createPoolConfig.tranches[i].interestRate);
            _poolConfiguration.tranches[i].interestRate = createPoolConfig.tranches[i].interestRate;

            // initialize future tranche interest rates array
            _futureTrancheInterests[lendingPoolInfo_.trancheAddresses[i]].push(
                FutureTrancheInterestRates({epoch: 0, interestRate: createPoolConfig.tranches[i].interestRate})
            );

            // allow tranches to spend the lending pool tokens
            _approve(address(this), lendingPoolInfo_.trancheAddresses[i], type(uint256).max);
        }

        // set tranche ratios
        uint256[] memory trancheRatios = new uint256[](createPoolConfig.tranches.length);
        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            trancheRatios[i] = createPoolConfig.tranches[i].ratio;
        }

        _updateTrancheDesiredRatios(trancheRatios);

        nextLossId = 1;

        return _poolConfiguration;
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Decimals of the lending pool token.
     * @return Decimals of the lending pool token.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Returns the pending pool address corresponding to the lending pool.
     * @return The pending pool address.
     */
    function pendingPool() public view returns (address) {
        return _lendingPoolInfo.pendingPool;
    }

    /**
     * @notice Returns the total user balance of the lending pool.
     * @dev Users' balance form all tranches.
     * @param user The user address.
     * @return userPoolBalance Total balance of the lending pool in the underlying asset.
     */
    function userBalance(address user) external view returns (uint256 userPoolBalance) {
        uint256 trancheCount = _lendingPoolInfo.trancheAddresses.length;
        for (uint256 i; i < trancheCount; ++i) {
            ILendingPoolTranche tranche = ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]);
            userPoolBalance += tranche.userActiveAssets(user);
        }
    }

    /**
     * @notice Returns the lending pool address info.
     * @return Lending pool address info.
     */
    function lendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    /**
     * @notice Returns the pool configuration.
     * @return poolConfiguration_ Pool configuration.
     */
    function poolConfiguration() external view returns (PoolConfiguration memory poolConfiguration_) {
        poolConfiguration_ = _poolConfiguration;

        uint256 currentEpoch = _systemVariables.currentEpochNumber();
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            poolConfiguration_.tranches[i].interestRate =
                _trancheInterestRate(_lendingPoolInfo.trancheAddresses[i], currentEpoch);
        }
    }

    /**
     * @notice Returns the tranche configuration minimum and maximum deposit amount.
     * @param tranche The tranche address.
     * @return minDepositAmount Minimum deposit amount.
     * @return maxDepositAmount Maximum deposit amount.
     */
    function trancheConfigurationDepositLimits(address tranche)
        external
        view
        verifyTranche(tranche)
        returns (uint256 minDepositAmount, uint256 maxDepositAmount)
    {
        return (
            _poolConfiguration.tranches[_trancheIndexUnverified(tranche)].minDepositAmount,
            _poolConfiguration.tranches[_trancheIndexUnverified(tranche)].maxDepositAmount
        );
    }

    /**
     * @notice Returns whether the address is a tranche of this lending pool.
     * @param tranche The tranche address.
     * @return Whether the address is a tranche of this lending pool.
     */
    function isLendingPoolTranche(address tranche) public view returns (bool) {
        return _trancheIndex[tranche] != 0;
    }

    /**
     * @notice Returns the tranche index of the lending pool.
     * @param tranche The tranche address.
     * @return The tranche index.
     */
    function trancheIndex(address tranche) external view verifyTranche(tranche) returns (uint256) {
        return _trancheIndexUnverified(tranche);
    }

    /// @notice Returns the tranche index of the lending pool without verifying the tranche.
    /// @dev Should only be used if the tranche is valid, otherwise it will revert.
    function _trancheIndexUnverified(address tranche) private view returns (uint256) {
        return _trancheIndex[tranche] - 1;
    }

    /**
     * @notice Returns the tranche addresses of the lending pool.
     * @return The tranche addresses array.
     */
    function lendingPoolTranches() external view returns (address[] memory) {
        return _lendingPoolInfo.trancheAddresses;
    }

    /**
     * @notice Returns the tranche count of the lending pool.
     * @return The tranche count.
     */
    function lendingPoolTrancheCount() external view returns (uint256) {
        return _lendingPoolInfo.trancheAddresses.length;
    }

    /**
     * @notice Returns the available funds of the lending pool.
     * @return The available funds of the lending pool in the underlying asset.
     */
    function availableFunds() public view returns (uint256) {
        return totalSupply() - userOwedAmount;
    }

    /**
     * @notice Returns the clearing configuration of the lending pool.
     * @return The clearing configuration of the lending pool.
     */
    function clearingConfiguration() external view returns (ClearingConfiguration memory) {
        uint256[] memory trancheRatios = new uint256[](_poolConfiguration.tranches.length);
        for (uint256 i; i < _poolConfiguration.tranches.length; ++i) {
            trancheRatios[i] = _poolConfiguration.tranches[i].ratio;
        }

        return ClearingConfiguration(
            _poolConfiguration.desiredDrawAmount,
            trancheRatios,
            _poolConfiguration.targetExcessLiquidityPercentage,
            _poolConfiguration.minimumExcessLiquidityPercentage
        );
    }

    /**
     * @notice Verifies the clearing configuration for the lending pool.
     * @dev Verifies the clearing configuration.
     * @param clearingConfig The clearing configuration to verify.
     */
    function verifyClearingConfig(ClearingConfiguration calldata clearingConfig) external view {
        if (isLendingPoolStopped) {
            if (
                clearingConfig.drawAmount != 0 || clearingConfig.maxExcessPercentage != 0
                    || clearingConfig.minExcessPercentage != 0
            ) {
                revert PoolConfigurationIsIncorrect("Clearing values must be 0 if the pool is stopped");
            }
        }

        if (clearingConfig.minExcessPercentage > clearingConfig.maxExcessPercentage) {
            revert PoolConfigurationIsIncorrect("minExcessPercentage more than maxExcessPercentage");
        }

        _verifyTrancheDesiredRatios(clearingConfig.trancheDesiredRatios);
    }

    /**
     * @notice Returns the maximum loss amount of the lending pool that can be reported.
     * @dev Returns the first loss capita amount plus the sum of the maximum loss amount of each tranche.
     * The loss amount can't be greater than the user owed amount. If it is, returns the user owed amount.
     * @return maximumLossAmount The maximum loss amount of the lending pool that can be reported.
     */
    function calculateMaximumLossAmount() public view returns (uint256 maximumLossAmount) {
        maximumLossAmount = firstLossCapital;

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            uint256 trancheMaximumLossAmount =
                ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]).calculateMaximumLossAmount();
            maximumLossAmount += trancheMaximumLossAmount;
        }

        if (userOwedAmount < maximumLossAmount) {
            maximumLossAmount = userOwedAmount;
        }
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    // #### CLEARING #### //

    /**
     * @notice Accepts the deposit of the user.
     * @dev This function is called by the pending pool.
     * Transfers the assets from the pending pool to the lending pool.
     * Mints the lending pool token.
     * Mints tranche shares to the user.
     * @param tranche The tranche address the deposit is accepted to.
     * @param user The user address.
     * @param acceptedAmount The amount of the deposit that is accepted.
     */
    function acceptDeposit(address tranche, address user, uint256 acceptedAmount)
        external
        lendingPoolShouldNotBeStopped
        onlyPendingPool
        verifyTranche(tranche)
        returns (uint256 trancheSharesMinted)
    {
        // transfer usdc from pending pool to lending pool - pre-approved
        _transferAssetsFrom(msg.sender, address(this), acceptedAmount);

        // mint lending pool tokens, the same amount as the accepted usdc deposit
        _mint(address(this), acceptedAmount);

        // transfer lending pool tokens from lending pool to the user in tranche - creates tranche shares for user
        trancheSharesMinted = ILendingPoolTranche(tranche).deposit(acceptedAmount, user);

        emit DepositAccepted(user, tranche, acceptedAmount, trancheSharesMinted);
    }

    /**
     * @notice Accepts the withdrawal of the user from a tranche.
     * @dev This function is called by the pending pool.
     * Burns tranche shares from the user.
     * Burns the lending pool token.
     * Transfers the assets from the tranche to the user.
     * @param tranche The tranche address.
     * @param user The user address.
     * @param acceptedShares The amount of the withdrawal that is accepted.
     * @return assetAmount The amount of the underlying asset that is withdrawn and transferred to the user.
     */
    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        onlyPendingPool
        verifyTranche(tranche)
        returns (uint256 assetAmount)
    {
        // transfer lending pool tokens from tranche to lending pool and burn tranche shares
        assetAmount = ILendingPoolTranche(tranche).redeem(acceptedShares, address(this), msg.sender);
        // inform tranche user shares were redeemed.
        ILendingPoolTranche(tranche).removeUserActiveShares(user, acceptedShares);

        // burn the lending pool token
        _burn(address(this), assetAmount);

        // transfer usdc to the user
        _transferAssets(user, assetAmount);

        emit WithdrawalAccepted(user, tranche, acceptedShares, assetAmount);
    }

    /**
     * @notice Applies the interests to the lending pool and the tranches.
     * @dev This function is called by the clearing coordinator.
     * Applies the interests to the lending pool tranches.
     * Mints the lending pool tokens to the tranches.
     * Increases the owed amount by the interest amount.
     * @param epoch The epoch number for which the interests are applied.
     */
    function applyInterests(uint256 epoch) external onlyClearingCoordinator {
        _updateTrancheInterestRateConfig(epoch);

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _applyTrancheInterest(_lendingPoolInfo.trancheAddresses[i], epoch);
        }
    }

    /**
     * @notice Applies the fixed rate interests to the lending pool and the tranches.
     * @dev This function is called by the fixed term deposit contract during the clearing.
     * Applies the fixed rate interests to the lending pool tranches.
     * Calculated the difference between the fixed rate and the current base rate and applies the difference.
     * @param user The user address.
     * @param tranche The tranche address.
     * @param trancheShares The amount of the tranche shares.
     * @param interestRate The interest rate.
     * @param epoch The epoch number for which the interests are applied.
     */
    function applyFixedRateInterests(
        address user,
        address tranche,
        uint256 trancheShares,
        uint256 interestRate,
        uint256 epoch
    ) external onlyFixedTermDeposit {
        _applyFixedRateInterests(user, tranche, trancheShares, interestRate, epoch);
    }

    /**
     * @notice Pay the lending pool owed fees from available balance.
     * @dev Tries to repay fees from the available balance.
     * Called by the clearing coordinator at the end of the clearing.
     */
    function payOwedFees() external onlyClearingCoordinator {
        uint256 availableAmount = availableFunds();

        // pay up to the owed fees amount
        uint256 feesPaid = _payFees(availableAmount);

        userOwedAmount += feesPaid;

        emit PaidFeesFromAvailableFunds(feesPaid);
    }

    // #### POOL DELEGATE #### //

    /**
     * @notice Draw assets from the lending pool to the draw recipient address.
     * @dev Decrease the desired draw amount by the draw amount.
     * Called by the clearing coordinator.
     * @param drawAmount The desired draw amount.
     */
    function drawFunds(uint256 drawAmount) external onlyClearingCoordinator lendingPoolShouldNotBeStopped {
        _draw(drawAmount);
        emit FundsDrawn(drawAmount);
    }

    /**
     * @notice Repays the owed funds to the lending pool of the desired amount.
     * @dev First we repay the owed fees, then we repay the user owed amount.
     * @param amount The amount of the repayment.
     */
    function repayOwedFunds(uint256 amount) external onlyLendingPoolManager verifyClearingNotPending {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (amount > userOwedAmount + feesOwedAmount) {
            revert RepayAmountCantBeGreaterThanOwedAmount(amount, userOwedAmount + feesOwedAmount);
        }

        _transferAssetsFrom(msg.sender, address(this), amount);

        uint256 feesPaid = _payFees(amount);

        uint256 userRepaidAmount = amount - feesPaid;

        userOwedAmount -= userRepaidAmount;

        emit OwedFundsRepaid(userRepaidAmount, feesPaid);
    }

    /**
     * @notice Reports the loss of the lending pool.
     * @dev Applies the loss first to the first loss capital.
     * If there is no more first loss capital,
     * the loss is applied to the tranches in order from the junior to the senior.
     * Burns tranche shares if needed.
     * Burns the lending pool token in te amount of the loss.
     * @param lossAmount The amount of the loss. Shouldn't be more than the maximum loss amount.
     * @param doMintLossTokens If true, mints loss tokens to all the users.
     * @return lossId The id of the loss.
     */
    function reportLoss(uint256 lossAmount, bool doMintLossTokens)
        external
        onlyLendingPoolManager
        verifyClearingNotPending
        returns (uint256 lossId)
    {
        // verify input
        if (lossAmount == 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than maximum loss amount
        uint256 maxLossAmount = calculateMaximumLossAmount();
        if (lossAmount > maxLossAmount) {
            revert LossAmountCantBeGreaterThanMaxLossAmount(lossAmount, maxLossAmount);
        }

        // get loss id and increment next loss id
        lossId = nextLossId;
        nextLossId++;

        uint256 lossLeft = lossAmount;

        // remove the amount from the first loss capital
        if (lossLeft > firstLossCapital) {
            unchecked {
                lossLeft -= firstLossCapital;
            }
        } else {
            lossLeft = 0;
        }

        if (lossLeft < lossAmount) {
            uint256 firstLossCapitalLoss = lossAmount - lossLeft;

            firstLossCapital -= firstLossCapitalLoss;
            _burn(address(this), firstLossCapitalLoss);

            emit FirstLossCapitalLossReported(lossId, firstLossCapitalLoss);
        }

        // remove the funds from the tranches and mint loss tokens if first loss capital is not enough
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            if (lossLeft > 0) {
                uint256 trancheLossApplied = ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i])
                    .registerTrancheLoss(lossId, lossLeft, doMintLossTokens);

                // lending pool tranche should return tokens
                _burn(_lendingPoolInfo.trancheAddresses[i], trancheLossApplied);

                lossLeft -= trancheLossApplied;
            } else {
                break;
            }
        }

        uint256 appliedLoss = lossAmount - lossLeft;

        userOwedAmount -= appliedLoss;

        emit LossReported(appliedLoss);
    }

    /**
     * @notice Repays the loss of the lending pool tranche for the loss id.
     * @param tranche The tranche address.
     * @param lossId The id of the loss.
     * @param amount The amount of the loss to repay.
     */
    function repayLoss(address tranche, uint256 lossId, uint256 amount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
        verifyLossId(lossId)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(tranche, amount);
        ILendingPoolTranche(tranche).repayLoss(lossId, amount);
    }

    /**
     * @notice Deposits the first loss capital to the lending pool.
     * @dev Transfers the assets to the lending pool.
     * Mints the lending pool token to itself.
     * @param amount The amount of the first loss capital to deposit.
     */
    function depositFirstLossCapital(uint256 amount) external lendingPoolShouldNotBeStopped onlyLendingPoolManager {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        _transferAssetsFrom(msg.sender, address(this), amount);

        _mint(address(this), amount);

        firstLossCapital += amount;

        emit FirstLossCapitalAdded(amount);
    }

    /**
     * @notice Withdraws the first loss capital from the lending pool.
     * @dev Can only be called once lending pool is stopped.
     * Transfers the assets to the first loss capital receiver.
     * Burns the lending pool token.
     * @param withdrawAmount The amount of the first loss capital to withdraw.
     * @param withdrawAddress The address to withdraw the first loss capital to.
     */
    function withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress)
        external
        onlyLendingPoolManager
        lendingPoolShouldBeStopped
    {
        AddressLib.checkIfZero(withdrawAddress);

        if (withdrawAmount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (withdrawAmount > firstLossCapital) {
            revert WithdrawAmountCantBeGreaterThanFirstLostCapital(withdrawAmount, firstLossCapital);
        }

        firstLossCapital -= withdrawAmount;

        _burn(address(this), withdrawAmount);

        _transferAssets(withdrawAddress, withdrawAmount);

        emit FirstLossCapitalWithdrawn(withdrawAmount);
    }

    /**
     * @notice Forces the immediate withdrawal of the user from the tranche.
     * @dev Burns tranche shares from the user.
     * Burns the lending pool token.
     * Transfers the assets from the tranche to the user.
     * @param tranche The tranche address.
     * @param user The user address.
     * @param sharesToWithdraw The amount of the shares to withdraw.
     * @return assetAmount The amount of the underlying asset that is withdrawn and transferred to the user.
     */
    function forceImmediateWithdrawal(address tranche, address user, uint256 sharesToWithdraw)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
        verifyClearingNotPending
        returns (uint256 assetAmount)
    {
        // transfer lending pool tokens from tranche to lending pool and burn tranche user shares
        assetAmount = ILendingPoolTranche(tranche).redeem(sharesToWithdraw, address(this), user);

        // burn the lending pool token
        _burn(address(this), assetAmount);

        // transfer usdc to the user
        _transferAssets(user, assetAmount);

        emit ImmediateWithdrawal(user, tranche, sharesToWithdraw, assetAmount);
    }

    /**
     * @notice Stops the lending pool.
     * @dev Stops the lending pool.
     * Can only be stopped if all owed amounts are repaid.
     * After stopping the lending pool, the lending pool can't accept new deposits.
     * The pool can't be resumed after stopping.
     * Sets the interest rates of the tranches to zero.
     */
    function stop() external onlyLendingPoolManager verifyClearingNotPending lendingPoolShouldNotBeStopped {
        if (userOwedAmount > 0) {
            revert UserOwedAmountIsGreaterThanZero(userOwedAmount);
        }

        if (feesOwedAmount > 0) {
            revert FeesOwedAmountIsGreaterThanZero(feesOwedAmount);
        }

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _poolConfiguration.tranches[i].interestRate = 0;

            address tranche = _lendingPoolInfo.trancheAddresses[i];

            delete _futureTrancheInterests[tranche];
            delete _trancheInterestIndex[tranche];

            _futureTrancheInterests[tranche].push(FutureTrancheInterestRates({epoch: 0, interestRate: 0}));

            _updateMinimumTrancheDepositAmount(tranche, 0);
            _updateMaximumTrancheDepositAmount(tranche, 0);
        }

        _updateDesiredDrawAmount(0);
        _updateMinimumExcessLiquidityPercentage(0);
        _updateTargetExcessLiquidityPercentage(0);

        IPendingPool(pendingPool()).stop();

        _stopLendingPool();

        emit LendingPoolStopped();
    }

    // #### USER #### //

    /**
     * @notice Claims the repaid loss of the lending pool tranche for the loss id.
     * @param user Claiming user address.
     * @param tranche The tranche address.
     * @param lossId The id of the loss.
     * @return claimedAmount The amount of the loss that is claimed.
     */
    function claimRepaidLoss(address user, address tranche, uint256 lossId)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
        verifyLossId(lossId)
        returns (uint256 claimedAmount)
    {
        claimedAmount = ILendingPoolTranche(tranche).claimRepaidLoss(user, lossId);
    }

    // #### CONFIG #### //

    /**
     * @notice Updates the draw recipient address.
     * @param drawRecipient The draw recipient address.
     */
    function updateDrawRecipient(address drawRecipient) external onlyLendingPoolManager {
        _updateDrawRecipient(drawRecipient);
    }

    /**
     * @notice Updates the minimum deposit amount of the tranche.
     * @param tranche The tranche address.
     * @param minimumDepositAmount The minimum deposit amount.
     */
    function updateMinimumDepositAmount(address tranche, uint256 minimumDepositAmount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _updateMinimumTrancheDepositAmount(tranche, minimumDepositAmount);
    }

    /**
     * @notice Updates the maximum deposit amount of the tranche.
     * @param tranche The tranche address.
     * @param maximumDepositAmount The maximum deposit amount.
     */
    function updateMaximumDepositAmount(address tranche, uint256 maximumDepositAmount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _updateMaximumTrancheDepositAmount(tranche, maximumDepositAmount);
    }

    /**
     * @notice Updates the interest rate of the tranche.
     * @dev The interest rate is updated for the future epoch depending on the epoch delay.
     * _futureTrancheInterests should always have at least one element.
     * @param tranche The tranche address.
     * @param interestRate The interest rate.
     */
    function updateTrancheInterestRate(address tranche, uint256 interestRate)
        external
        lendingPoolShouldNotBeStopped
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _verifyTrancheInterestRate(interestRate);

        uint256 epochDelay = _poolConfiguration.trancheInterestChangeEpochDelay;
        uint256 currentEpoch = _systemVariables.currentEpochNumber();
        uint256 applicableEpoch = currentEpoch + epochDelay;

        for (uint256 i = _futureTrancheInterests[tranche].length - 1; i > 0; --i) {
            if (_futureTrancheInterests[tranche][i].epoch > applicableEpoch) {
                FutureTrancheInterestRates memory futureTrancheInterest = _futureTrancheInterests[tranche][i];
                _futureTrancheInterests[tranche].pop();

                emit RemovedTrancheInterestRateUpdate(tranche, futureTrancheInterest.epoch, i);
            } else {
                break;
            }
        }

        if (_futureTrancheInterests[tranche][_futureTrancheInterests[tranche].length - 1].epoch == applicableEpoch) {
            _futureTrancheInterests[tranche][_futureTrancheInterests[tranche].length - 1].interestRate = interestRate;
        } else {
            _futureTrancheInterests[tranche].push(
                FutureTrancheInterestRates({epoch: applicableEpoch, interestRate: interestRate})
            );
        }

        emit UpdatedTrancheInterestRate(tranche, applicableEpoch, interestRate);
    }

    /**
     * @notice Updates the tranche desired ratios.
     * @dev The sum of the ratios should be 100%.
     * @param ratios The desired ratios of the tranches.
     */
    function updateTrancheDesiredRatios(uint256[] memory ratios)
        external
        onlyLendingPoolManager
        verifyClearingNotPending
    {
        _updateTrancheDesiredRatios(ratios);
    }

    /**
     * @notice Updates the tranche interest rate change epoch delay.
     * @param epochDelay The epoch delay for the interest rate change.
     */
    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external onlyLendingPoolManager {
        _updateTrancheInterestRateChangeEpochDelay(epochDelay);
    }

    /**
     * @notice Updates the desired draw amount.
     * @param desiredDrawAmount The desired draw amount.
     */
    function updateDesiredDrawAmount(uint256 desiredDrawAmount)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
        verifyClearingNotPending
    {
        _updateDesiredDrawAmount(desiredDrawAmount);
    }

    /**
     * @notice Updates the target excess liquidity percentage. Used to calculate how much excess liquidity should be accepted based on the user owed amount.
     * @param targetExcessLiquidityPercentage The target excess liquidity percentage.
     */
    function updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
        verifyClearingNotPending
    {
        _updateTargetExcessLiquidityPercentage(targetExcessLiquidityPercentage);
    }

    /**
     * @notice Updates the minimum excess liquidity percentage. Used to calculate how much excess liquidity should stay in the lending pool if there are more withdrawals.
     * @param minimumExcessLiquidityPercentage The minimum excess liquidity percentage.
     */
    function updateMinimumExcessLiquidityPercentage(uint256 minimumExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
        verifyClearingNotPending
    {
        _updateMinimumExcessLiquidityPercentage(minimumExcessLiquidityPercentage);
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _trancheConfigurationStorage(address tranche) internal view returns (TrancheConfig storage) {
        return _poolConfiguration.tranches[_trancheIndexUnverified(tranche)];
    }

    function _verifyTrancheInterestRate(uint256 interestRate) private view {
        if (interestRate > _systemVariables.maxTrancheInterestRate()) {
            revert PoolConfigurationIsIncorrect("Interest rate is more than max allowed");
        }
    }

    function _verifyTrancheDesiredRatios(uint256[] memory ratios) private view {
        if (ratios.length != _lendingPoolInfo.trancheAddresses.length) {
            revert InvalidArrayLength();
        }

        uint256 ratiosSum;
        for (uint256 i; i < ratios.length; ++i) {
            ratiosSum += ratios[i];
        }

        if (ratiosSum != FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("Invalid tranche ratio sum");
        }
    }

    function _trancheInterestRateIndex(address tranche, uint256 epoch) private view returns (uint256 index) {
        index = _trancheInterestIndex[tranche];

        for (uint256 i = index + 1; i < _futureTrancheInterests[tranche].length; ++i) {
            if (_futureTrancheInterests[tranche][i].epoch <= epoch) {
                index++;
            } else {
                break;
            }
        }
    }

    function _trancheInterestRate(address tranche, uint256 epoch) private view returns (uint256 interestRate) {
        uint256 index = _trancheInterestRateIndex(tranche, epoch);
        interestRate = _futureTrancheInterests[tranche][index].interestRate;
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _applyTrancheInterest(address tranche, uint256 epoch) internal {
        uint256 trancheAssetBalance = balanceOf(tranche);
        if (trancheAssetBalance == 0) return;

        uint256 interestAmount =
            trancheAssetBalance * _trancheConfigurationStorage(tranche).interestRate / INTEREST_RATE_FULL_PERCENT;

        // calculate fees
        uint256 feesAmount = interestAmount * _systemVariables.performanceFee() / FULL_PERCENT;

        // decrease by the fee percentage
        uint256 userInterestAmount = interestAmount - feesAmount;

        // increase owed amount
        feesOwedAmount += feesAmount;
        userOwedAmount += userInterestAmount;

        // mint the lending pool tokens to the lending pool tranche
        _mint(tranche, userInterestAmount);

        emit InterestApplied(tranche, epoch, userInterestAmount);
        emit FeesOwedIncreased(epoch, feesAmount);
    }

    function _applyFixedRateInterests(
        address user,
        address tranche,
        uint256 trancheShares,
        uint256 fixedInterestRate,
        uint256 epoch
    ) internal returns (int256 sharesDiff) {
        uint256 baseTrancheInterestRate = _trancheConfigurationStorage(tranche).interestRate;
        if (fixedInterestRate == baseTrancheInterestRate) {
            return 0;
        }

        uint256 balanceAfterFixedInterest;
        uint256 balanceAfterBaseInterest;

        {
            uint256 assets = ILendingPoolTranche(tranche).convertToAssets(trancheShares);

            if (assets == 0) return 0;

            uint256 balanceBeforeBaseInterest = assets * INTEREST_RATE_FULL_PERCENT
                / (
                    INTEREST_RATE_FULL_PERCENT
                        + ((baseTrancheInterestRate * (FULL_PERCENT - _systemVariables.performanceFee())) / FULL_PERCENT)
                );

            balanceAfterFixedInterest = balanceBeforeBaseInterest * fixedInterestRate / INTEREST_RATE_FULL_PERCENT;
            balanceAfterBaseInterest = balanceBeforeBaseInterest * baseTrancheInterestRate / INTEREST_RATE_FULL_PERCENT;
        }

        if (balanceAfterFixedInterest > balanceAfterBaseInterest) {
            // fixed term yield is higher than base interest - deposit the difference
            uint256 interestAmountDiff = balanceAfterFixedInterest - balanceAfterBaseInterest;
            uint256 fees = interestAmountDiff * _systemVariables.performanceFee() / FULL_PERCENT;
            uint256 userInterestAmountDiff = interestAmountDiff - fees;

            if (userInterestAmountDiff == 0) return 0;

            _mint(address(this), userInterestAmountDiff);
            sharesDiff = int256(ILendingPoolTranche(tranche).deposit(userInterestAmountDiff, user));
            ILendingPoolTranche(tranche).transferFrom(user, address(_fixedTermDeposit), uint256(sharesDiff));

            feesOwedAmount += fees;
            userOwedAmount += userInterestAmountDiff;

            emit FixedInterestDiffApplied(user, tranche, epoch, sharesDiff, int256(userInterestAmountDiff));
            emit FeesOwedIncreased(epoch, fees);
        } else if (balanceAfterFixedInterest < balanceAfterBaseInterest) {
            // fixed term yield is lower than base interest - withdraw the difference
            uint256 interestAmountDiff = balanceAfterBaseInterest - balanceAfterFixedInterest;
            uint256 overpaidFees = interestAmountDiff * _systemVariables.performanceFee() / FULL_PERCENT;
            uint256 userInterestAmountDiff = interestAmountDiff - overpaidFees;

            uint256 sharesToWithdraw = ILendingPoolTranche(tranche).previewWithdraw(userInterestAmountDiff);

            if (sharesToWithdraw == 0) return 0;

            {
                uint256 assetAmount =
                    ILendingPoolTranche(tranche).redeem(sharesToWithdraw, address(this), address(_fixedTermDeposit));
                _burn(address(this), assetAmount);
            }

            ILendingPoolTranche(tranche).removeUserActiveShares(user, sharesToWithdraw);

            sharesDiff = -int256(sharesToWithdraw);

            feesOwedAmount -= overpaidFees;
            userOwedAmount -= userInterestAmountDiff;

            emit FixedInterestDiffApplied(user, tranche, epoch, sharesDiff, -int256(userInterestAmountDiff));
            emit FeesOwedDecreased(epoch, overpaidFees);
        }
    }

    function _draw(uint256 drawAmount) private {
        if (drawAmount == 0) return;

        uint256 availableAmount = availableFunds();
        if (availableAmount < drawAmount) {
            revert DrawAmountCantBeGreaterThanAvailableAmount(drawAmount, availableAmount);
        }

        userOwedAmount += drawAmount;

        if (_poolConfiguration.desiredDrawAmount > drawAmount) {
            unchecked {
                _updateDesiredDrawAmount(_poolConfiguration.desiredDrawAmount - drawAmount);
            }
        } else {
            _updateDesiredDrawAmount(0);
        }

        _transferAssets(_poolConfiguration.drawRecipient, drawAmount);
    }

    function _payFees(uint256 amount) private returns (uint256 feesPaid) {
        if (amount == 0) return feesPaid;

        if (amount > feesOwedAmount) {
            feesPaid = feesOwedAmount;
            feesOwedAmount = 0;
        } else {
            feesPaid = amount;
            unchecked {
                feesOwedAmount -= amount;
            }
        }

        _approveAsset(address(_feeManager), feesPaid);
        _feeManager.emitFees(feesPaid);

        emit PaidFees(feesPaid);
    }

    function _updateDrawRecipient(address drawRecipient) private {
        AddressLib.checkIfZero(drawRecipient);
        _poolConfiguration.drawRecipient = drawRecipient;

        emit UpdatedDrawRecipient(drawRecipient);
    }

    function _updateMinimumTrancheDepositAmount(address tranche, uint256 minimumDepositAmount) private {
        if (minimumDepositAmount > _poolConfiguration.tranches[_trancheIndexUnverified(tranche)].maxDepositAmount) {
            revert PoolConfigurationIsIncorrect("Minimum deposit shouldn't be more than max deposit amount");
        }

        _trancheConfigurationStorage(tranche).minDepositAmount = minimumDepositAmount;

        emit UpdatedMinimumDepositAmount(tranche, minimumDepositAmount);
    }

    function _updateMaximumTrancheDepositAmount(address tranche, uint256 maximumDepositAmount) private {
        if (maximumDepositAmount < _poolConfiguration.tranches[_trancheIndexUnverified(tranche)].minDepositAmount) {
            revert PoolConfigurationIsIncorrect("Maximum deposit shouldn't be less than min deposit amount");
        }

        _trancheConfigurationStorage(tranche).maxDepositAmount = maximumDepositAmount;

        emit UpdatedMaximumDepositAmount(tranche, maximumDepositAmount);
    }

    function _updateTrancheDesiredRatios(uint256[] memory ratios) private {
        _verifyTrancheDesiredRatios(ratios);

        for (uint256 i; i < ratios.length; ++i) {
            _poolConfiguration.tranches[i].ratio = ratios[i];
        }

        emit UpdatedTrancheDesiredRatios(ratios);
    }

    function _updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) private {
        _poolConfiguration.trancheInterestChangeEpochDelay = epochDelay;

        emit UpdatedTrancheInterestRateChangeEpochDelay(epochDelay);
    }

    function _updateDesiredDrawAmount(uint256 desiredDrawAmount) private {
        _poolConfiguration.desiredDrawAmount = desiredDrawAmount;
        emit UpdatedDesiredDrawAmount(desiredDrawAmount);
    }

    function _updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage) private {
        if (targetExcessLiquidityPercentage < _poolConfiguration.minimumExcessLiquidityPercentage) {
            revert PoolConfigurationIsIncorrect(
                "Target excess liquidity percentage is less than minimum excess liquidity percentage"
            );
        }

        _poolConfiguration.targetExcessLiquidityPercentage = targetExcessLiquidityPercentage;

        emit UpdatedTargetExcessLiquidityPercentage(targetExcessLiquidityPercentage);
    }

    function _updateMinimumExcessLiquidityPercentage(uint256 minimumExcessLiquidityPercentage) private {
        if (minimumExcessLiquidityPercentage > _poolConfiguration.targetExcessLiquidityPercentage) {
            revert PoolConfigurationIsIncorrect(
                "Minimum excess liquidity percentage is more than target excess liquidity percentage"
            );
        }

        _poolConfiguration.minimumExcessLiquidityPercentage = minimumExcessLiquidityPercentage;

        emit UpdatedMinimumExcessLiquidityPercentage(minimumExcessLiquidityPercentage);
    }

    function _updateTrancheInterestRateConfig(uint256 epoch) private {
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            address tranche = _lendingPoolInfo.trancheAddresses[i];
            uint256 index = _trancheInterestRateIndex(tranche, epoch);
            uint256 oldIndex = _trancheInterestIndex[tranche];

            if (index > oldIndex) {
                _trancheInterestIndex[tranche] = index;
                _poolConfiguration.tranches[i].interestRate = _futureTrancheInterests[tranche][index].interestRate;
            } else if (
                _poolConfiguration.tranches[i].interestRate != _futureTrancheInterests[tranche][oldIndex].interestRate
            ) {
                _poolConfiguration.tranches[i].interestRate = _futureTrancheInterests[tranche][oldIndex].interestRate;
            }
        }
    }

    function _setTrancheIndex(address tranche, uint256 index) internal {
        _trancheIndex[tranche] = index + 1;
    }

    function _onlyPendingPool() private view {
        if (msg.sender != pendingPool()) {
            revert OnlyOwnPendingPool(msg.sender, pendingPool());
        }
    }

    function _onlyLendingPoolManager() private view {
        if (msg.sender != _lendingPoolManager) {
            revert OnlyLendingPoolManager();
        }
    }

    function _onlyClearingCoordinator() private view {
        if (msg.sender != address(_clearingCoordinator)) {
            revert OnlyClearingCoordinator();
        }
    }

    function _verifyTranche(address tranche) private view {
        if (!isLendingPoolTranche(tranche)) {
            revert InvalidTranche(address(this), tranche);
        }
    }

    function _isLossIdValid(uint256 lossId) private view {
        if (lossId >= nextLossId || lossId == 0) {
            revert LossIdNotValid(lossId);
        }
    }

    function _verifyClearingNotPending() private view {
        if (_clearingCoordinator.isLendingPoolClearingPending(address(this))) {
            revert ClearingIsPending();
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyPendingPool() {
        _onlyPendingPool();
        _;
    }

    modifier onlyLendingPoolManager() {
        _onlyLendingPoolManager();
        _;
    }

    modifier onlyClearingCoordinator() {
        _onlyClearingCoordinator();
        _;
    }

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }

    modifier verifyLossId(uint256 lossId) {
        _isLossIdValid(lossId);
        _;
    }

    modifier verifyClearingNotPending() {
        _verifyClearingNotPending();
        _;
    }

    modifier onlyFixedTermDeposit() {
        if (msg.sender != address(_fixedTermDeposit)) {
            revert OnlyFixedTermDeposit();
        }
        _;
    }
}
