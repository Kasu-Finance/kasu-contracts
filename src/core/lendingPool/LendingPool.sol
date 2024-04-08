// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/ISystemVariables.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../interfaces/IFeeManager.sol";
import "../AssetFunctionsBase.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "./LendingPoolStoppable.sol";
import "../Constants.sol";
import "../../shared/AddressLib.sol";

struct FutureTrancheInterestRates {
    uint256 epoch;
    uint256 interestRate;
}

/**
 * @title LendingPool contract
 * @notice This contract is the ledger of the lending pool balances.
 * @dev
 * The lending pool is also a ERC20 token. This token always represents
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
    ISystemVariables public immutable systemVariables;
    /// @notice Lending pool manager address.
    address public immutable lendingPoolManager;
    /// @notice Clearing coordinator contract.
    IClearingCoordinator public immutable clearingCoordinator;
    /// @notice Fee manager contract.
    IFeeManager public immutable feeManager;

    /// @notice Lending pool info contains pending pool and tranche addresses.
    LendingPoolInfo private _lendingPoolInfo;
    /// @notice Lending pool configuration.
    PoolConfiguration private _poolConfiguration;
    /// @notice The index of lending pool info and pool configuration
    mapping(address tranche => uint256 index) private _trancheIndex;

    /// @notice Future epoch tranche interest rates.
    mapping(address tranche => FutureTrancheInterestRates[]) private _futureTrancheInterests;
    /// @notice Current tranche interest index.
    mapping(address tranche => uint256) private _trancheInterestIndex;

    /// @notice Asset amount of fees owed.
    uint256 private _feesOwed;
    /// @notice Asset amount owed to the users.
    uint256 private _userOwedAmount;

    /// @notice First loss capital amount.
    uint256 public firstLossCapital;
    /// @notice The id of the next reported loss.
    uint256 public nextLossId;

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
        address underlyingAsset_
    ) AssetFunctionsBase(underlyingAsset_) {
        AddressLib.checkIfZero(address(systemVariables_));
        AddressLib.checkIfZero(lendingPoolManager_);
        AddressLib.checkIfZero(address(clearingCoordinator_));
        AddressLib.checkIfZero(address(feeManager_));

        systemVariables = systemVariables_;
        lendingPoolManager = lendingPoolManager_;
        clearingCoordinator = clearingCoordinator_;
        feeManager = feeManager_;

        _disableInitializers();
    }

    /**
     * @notice Initializes the lending pool.
     * @param createPoolConfig Create lending pool configuration.
     * @param lendingPoolInfo Lending pool info containing other addresses and configuration.
     */
    function initialize(CreatePoolConfig memory createPoolConfig, LendingPoolInfo memory lendingPoolInfo)
        public
        initializer
        returns (PoolConfiguration memory)
    {
        AddressLib.checkIfZero(createPoolConfig.poolAdmin);
        AddressLib.checkIfZero(createPoolConfig.drawRecipient);
        AddressLib.checkIfZero(lendingPoolInfo.pendingPool);

        __ERC20_init(createPoolConfig.poolName, createPoolConfig.poolSymbol);

        _lendingPoolInfo = lendingPoolInfo;

        // setup pool configuration
        _poolConfiguration.targetExcessLiquidityPercentage = createPoolConfig.targetExcessLiquidityPercentage;
        _poolConfiguration.drawRecipient = createPoolConfig.drawRecipient;
        _poolConfiguration.trancheInterestChangeEpochDelay = systemVariables.defaultTrancheInterestChangeEpochDelay();

        _updateDesiredDrawAmount(createPoolConfig.desiredDrawAmount);

        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            _poolConfiguration.tranches.push(
                TrancheConfig(
                    createPoolConfig.tranches[i].ratio,
                    createPoolConfig.tranches[i].interestRate,
                    createPoolConfig.tranches[i].minDepositAmount,
                    createPoolConfig.tranches[i].maxDepositAmount
                )
            );

            _futureTrancheInterests[lendingPoolInfo.trancheAddresses[i]].push(
                FutureTrancheInterestRates({epoch: 0, interestRate: createPoolConfig.tranches[i].interestRate})
            );

            _setTrancheIndex(lendingPoolInfo.trancheAddresses[i], i);

            _approve(address(this), lendingPoolInfo.trancheAddresses[i], type(uint256).max);
        }

        _verifyPoolConfiguration();

        nextLossId = 1;

        return _poolConfiguration;
    }

    /**
     * @notice Decimals of the lending pool token.
     * @return Decimals of the lending pool token.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Returns the lending pool address info.
     * @return Lending pool address info.
     */
    function getlendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    /**
     * @notice Returns the pool configuration.
     * @return poolConfiguration_ Pool configuration.
     */
    function poolConfiguration() external view returns (PoolConfiguration memory poolConfiguration_) {
        poolConfiguration_ = _poolConfiguration;

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            poolConfiguration_.tranches[i].interestRate =
                _getTrancheInterestRate(_lendingPoolInfo.trancheAddresses[i], currentEpoch);
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
            _poolConfiguration.tranches[getTrancheIndex(tranche)].minDepositAmount,
            _poolConfiguration.tranches[getTrancheIndex(tranche)].maxDepositAmount
        );
    }

    /**
     * @notice Returns the pending pool address corresponding to the lending pool.
     * @return The pending pool address.
     */
    function getPendingPool() public view returns (address) {
        return _lendingPoolInfo.pendingPool;
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
    function getTrancheIndex(address tranche) public view verifyTranche(tranche) returns (uint256) {
        return _trancheIndex[tranche] - 1;
    }

    /**
     * @notice Returns the tranche addresses of the lending pool.
     * @return The tranche addresses array.
     */
    function getLendingPoolTranches() external view returns (address[] memory) {
        return _lendingPoolInfo.trancheAddresses;
    }

    /**
     * @notice Returns the tranche count of the lending pool.
     * @return The tranche count.
     */
    function getLendingPoolTrancheCount() external view returns (uint256) {
        return _lendingPoolInfo.trancheAddresses.length;
    }

    /**
     * @notice Returns the user owed amount in asset that still needs to be repaid.
     * @return The user owed amount.
     */
    function getUserOwedAmount() external view returns (uint256) {
        return _userOwedAmount;
    }

    /**
     * @notice Returns the fees owed amount in asset that still needs to be repaid.
     * @return The fees owed amount.
     */
    function getFeesOwedAmount() external view returns (uint256) {
        return _feesOwed;
    }

    /**
     * @notice Returns the available funds of the lending pool.
     * @return The available funds of the lending pool in the underlying asset.
     */
    function getAvailableFunds() external view returns (uint256) {
        return totalSupply() - _userOwedAmount;
    }

    /**
     * @notice Returns the balance of the tranche.
     * @param tranche The tranche address.
     * @return Balance of the tranche in the underlying asset.
     */
    function getTrancheBalance(address tranche) external view verifyTranche(tranche) returns (uint256) {
        return balanceOf(tranche);
    }

    /**
     * @notice Returns the total user balance of the lending pool.
     * @dev Users' balance form all tranches.
     * @param user The user address.
     * @return availableBalance Total balance of the lending pool in the underlying asset.
     */
    function getUserBalance(address user) external view returns (uint256 availableBalance) {
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            ILendingPoolTranche tranche = ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]);
            availableBalance += tranche.getUserActiveAssets(user);
        }
    }

    /**
     * @notice Accepts the deposit of the user.
     * @dev
     * This function is called by the pending pool.
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

        emit DepositAccepted(user, tranche, acceptedAmount);
    }

    /**
     * @notice Accepts the withdrawal of the user from a tranche.
     * @dev
     * This function is called by the pending pool.
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
        // transfer tranche shares from the pending pool to the lending pool
        // ILendingPoolTranche(tranche).transferFrom(msg.sender, address(this), acceptedShares);

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
     * @dev
     * This function is called by the clearing coordinator.
     * Applies the interests to the lending pool tranches.
     * Mints the lending pool tokens to the tranches.
     * Increases the owed amount by the interest amount.
     * @param epoch The epoch number for which the interests are applied.
     */
    function applyInterests(uint256 epoch) external onlyClearingCoordinator {
        _applyInterests(epoch);
    }

    function _applyInterests(uint256 epoch) internal {
        _updateTrancheInterestRateConfig(epoch);

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _applyTrancheInterest(_lendingPoolInfo.trancheAddresses[i], epoch);
        }
    }

    /**
     * @notice Verifies the clearing configuration for the lending pool.
     * @dev
     * Verifies the clearing configuration.
     * @param clearingConfig The clearing configuration to verify.
     */
    function verifyClearingConfig(ClearingConfiguration calldata clearingConfig) external view {
        if (isLendingPoolStopped) {
            if (
                clearingConfig.drawAmount != 0 || clearingConfig.maxExcessPercentage != 0
                    || clearingConfig.minExcessPercentage != 0
            ) {
                revert PoolConfigurationIsIncorrect("drawAmount must be 0 if pool is stopped");
            }
        }

        if (clearingConfig.minExcessPercentage > clearingConfig.maxExcessPercentage) {
            revert PoolConfigurationIsIncorrect("minExcessPercentage more than maxExcessPercentage");
        }

        if (clearingConfig.maxExcessPercentage > FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("maxExcessPercentage more than 100");
        }

        if (_poolConfiguration.tranches.length != clearingConfig.trancheDesiredRatios.length) {
            revert PoolConfigurationIsIncorrect("incorrect tranche length");
        }

        uint256 ratiosSum;
        for (uint256 i; i < clearingConfig.trancheDesiredRatios.length; ++i) {
            ratiosSum += clearingConfig.trancheDesiredRatios[i];
        }
        if (ratiosSum != FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("invalid tranche ratio sum");
        }
    }

    /**
     * @notice Returns the clearing configuration of the lending pool.
     * @return The clearing configuration of the lending pool.
     */
    function getClearingConfig() external view returns (ClearingConfiguration memory) {
        uint256[] memory trancheRatios = new uint256[](_poolConfiguration.tranches.length);
        for (uint256 i; i < _poolConfiguration.tranches.length; ++i) {
            trancheRatios[i] = _poolConfiguration.tranches[i].ratio;
        }

        ClearingConfiguration memory clearingConfiguration = ClearingConfiguration(
            _poolConfiguration.desiredDrawAmount,
            trancheRatios,
            _poolConfiguration.targetExcessLiquidityPercentage,
            _poolConfiguration.minimumExcessLiquidityPercentage
        );

        return clearingConfiguration;
    }

    function _applyTrancheInterest(address tranche, uint256 epoch) internal {
        uint256 trancheAssetBalance = balanceOf(tranche);
        if (trancheAssetBalance == 0) return;

        uint256 interestAmount =
            trancheAssetBalance * _getTrancheConfiguration(tranche).interestRate / INTEREST_RATE_FULL_PERCENT;

        // calculate fees
        uint256 feesAmount = interestAmount * systemVariables.performanceFee() / FULL_PERCENT;

        // decrease by the fee percentage
        uint256 userInterestAmount = interestAmount - feesAmount;

        // increase owed amount
        _feesOwed += feesAmount;
        _userOwedAmount += userInterestAmount;

        // mint the lending pool tokens to the lending pool tranche
        _mint(tranche, userInterestAmount);

        emit InterestApplied(tranche, epoch, userInterestAmount);
        emit FeesOwedIncreased(epoch, feesAmount);
    }

    /**
     * @notice Draw assets from the lending pool to the draw recipient address.
     * @dev
     * Decrease the desired draw amount by the draw amount.
     * Called by the clearing coordinator.
     * @param drawAmount The desired draw amount.
     */
    function drawFunds(uint256 drawAmount) external onlyClearingCoordinator lendingPoolShouldNotBeStopped {
        _draw(drawAmount);
        emit FundsDrawn(drawAmount);
    }

    function _draw(uint256 drawAmount) internal {
        if (drawAmount == 0) return;

        uint256 availableAmount = _myAssetBalance();
        if (availableAmount < drawAmount) {
            revert DrawAmountCantBeGreaterThanAvailableAmount(drawAmount, availableAmount);
        }

        _userOwedAmount += drawAmount;

        if (_poolConfiguration.desiredDrawAmount > drawAmount) {
            unchecked {
                _updateDesiredDrawAmount(_poolConfiguration.desiredDrawAmount - drawAmount);
            }
        } else {
            _updateDesiredDrawAmount(0);
        }

        _transferAssets(_poolConfiguration.drawRecipient, drawAmount);
    }

    /**
     * @notice Repays the owed funds to the lending pool of the desired amount.
     * @dev First we repay the owed fees, then we repay the user owed amount.
     * @param amount The amount of the repayment.
     */
    function repayOwedFunds(uint256 amount) external onlyLendingPoolManager {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (amount > _userOwedAmount + _feesOwed) {
            revert RepayAmountCantBeGreaterThanOwedAmount(amount, _userOwedAmount + _feesOwed);
        }

        _transferAssetsFrom(msg.sender, address(this), amount);

        uint256 feesPaid = _payFees(amount);

        uint256 userRepaidAmount = amount - feesPaid;

        _userOwedAmount -= userRepaidAmount;

        emit OwedFundsRepaid(userRepaidAmount, feesPaid);
    }

    function _payFees(uint256 amount) private returns (uint256 feesPaid) {
        if (amount == 0) return feesPaid;

        if (amount > _feesOwed) {
            feesPaid = _feesOwed;
            _feesOwed = 0;
        } else {
            feesPaid = amount;
            unchecked {
                _feesOwed -= amount;
            }
        }

        _approveAsset(address(feeManager), feesPaid);
        feeManager.emitFees(feesPaid);

        emit PaidFees(feesPaid);
    }

    /**
     * @notice Returns the maximum loss amount of the lending pool that can be reported.
     * @dev
     * Returns the first loss capita amount plus the sum of the maximum loss amount of each tranche.
     * The loss amount can't be greater than the user owed amount. If it is, returns the user owed amount.
     * @return maximumLossAmount The maximum loss amount of the lending pool that can be reported.
     */
    function getMaximumLossAmount() public view returns (uint256 maximumLossAmount) {
        maximumLossAmount = firstLossCapital;

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            uint256 trancheMximumLossAmount =
                ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]).getMaximumLossAmount();
            maximumLossAmount += trancheMximumLossAmount;
        }

        if (_userOwedAmount < maximumLossAmount) {
            maximumLossAmount = _userOwedAmount;
        }
    }

    /**
     * @notice Reports the loss of the lending pool.
     * @dev
     * Applies the loss first to the first loss capital.
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
        if (systemVariables.isClearingTime()) {
            revert CannotExecuteDuringClearingTime();
        }

        // verify input
        if (lossAmount == 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than maximum loss amount
        uint256 maxLossAmount = getMaximumLossAmount();
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

        _userOwedAmount -= appliedLoss;

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

    /**
     * @notice Deposits the first loss capital to the lending pool.
     * @dev
     * Transfers the assets to the lending pool.
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

        emit FirstLossCapitalAdded(amount, firstLossCapital);
    }

    function withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress)
        external
        onlyLendingPoolManager
    {
        _withdrawFirstLossCapital(withdrawAmount, withdrawAddress);
    }

    function _withdrawFirstLossCapital(uint256 withdrawAmount, address withdrawAddress) internal {
        if (withdrawAmount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (withdrawAmount > firstLossCapital) {
            revert WithdrawAmountCantBeGreaterThanFirstLostCapital(withdrawAmount, firstLossCapital);
        }

        _transferAssets(withdrawAddress, withdrawAmount);

        _burn(address(this), withdrawAmount);

        firstLossCapital -= withdrawAmount;

        emit FirstLossCapitalWithdrawn(withdrawAmount, firstLossCapital);
    }

    /**
     * @notice Forces the immediate withdrawal of the user from the tranche.
     * @dev
     * Burns tranche shares from the user.
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
     * @dev
     * Stops the lending pool.
     * Can only be stopped if all owed amounts are repaid.
     * After stopping the lending pool, the lending pool can't accept new deposits.
     * The pool can't be resumed after stopping.
     * Withdraws the first loss capital to the first loss capital receiver.
     * Sets the interest rates of the tranches to zero.
     * @param firstLossCapitalReceiver The address of the first loss capital receiver.
     */
    function stop(address firstLossCapitalReceiver) external onlyLendingPoolManager verifyClearingNotPending {
        if (_userOwedAmount > 0) {
            revert UserOwedAmountIsGreaterThanZero(_userOwedAmount);
        }

        if (_feesOwed > 0) {
            revert FeesOwedAmountIsGreaterThanZero(_feesOwed);
        }

        AddressLib.checkIfZero(firstLossCapitalReceiver);

        if (firstLossCapital > 0) {
            _withdrawFirstLossCapital(firstLossCapital, firstLossCapitalReceiver);
        }

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _poolConfiguration.tranches[i].interestRate = 0;

            address tranche = _lendingPoolInfo.trancheAddresses[i];

            delete _futureTrancheInterests[tranche];
            delete _trancheInterestIndex[tranche];

            _futureTrancheInterests[tranche].push(FutureTrancheInterestRates({epoch: 0, interestRate: 0}));
            // TODO: emit event
        }

        _updateDesiredDrawAmount(0);
        // TODO: update excess liquidity percentage and max/min deposit to 0

        IPendingPool(getPendingPool()).stop();

        _stopLendingPool();

        emit LendingPoolStopped();
    }

    // config

    /**
     * @notice Updates the draw recipient address.
     * @param drawRecipient The draw recipient address.
     */
    function updateDrawRecipient(address drawRecipient) external onlyLendingPoolManager {
        AddressLib.checkIfZero(drawRecipient);
        _poolConfiguration.drawRecipient = drawRecipient;
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
        _getTrancheConfiguration(tranche).minDepositAmount = minimumDepositAmount;
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
        _getTrancheConfiguration(tranche).maxDepositAmount = maximumDepositAmount;
    }

    /**
     * @notice Updates the interest rate of the tranche.
     * @dev The interest rate is updated for the future epoch depending on the epoch delay.
     * @param tranche The tranche address.
     * @param interestRate The interest rate.
     */
    function updateTrancheInterestRate(address tranche, uint256 interestRate)
        external
        lendingPoolShouldNotBeStopped
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        uint256 maxTrancheInterestRate = systemVariables.maxTrancheInterestRate();

        if (interestRate > maxTrancheInterestRate) {
            revert PoolConfigurationIsIncorrect("interest rate is more than max allowed");
        }

        uint256 epochDelay = _poolConfiguration.trancheInterestChangeEpochDelay;
        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();
        uint256 applicableEpoch = currentEpoch + epochDelay;

        for (uint256 i = _futureTrancheInterests[tranche].length - 1; i > 0; --i) {
            if (_futureTrancheInterests[tranche][i].epoch >= applicableEpoch) {
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
    function updateTrancheDesiredRatios(uint256[] calldata ratios) external onlyLendingPoolManager {
        if (ratios.length != _lendingPoolInfo.trancheAddresses.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _getTrancheConfiguration(_lendingPoolInfo.trancheAddresses[i]).ratio = ratios[i];
        }

        _verifyPoolConfiguration();
    }

    /**
     * @notice Updates the tranche interest rate change epoch delay.
     * @param epochDelay The epoch delay for the interest rate change.
     */
    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external onlyLendingPoolManager {
        _poolConfiguration.trancheInterestChangeEpochDelay = epochDelay;
    }

    /**
     * @notice Updates the desired draw amount.
     * @param desiredDrawAmount The desired draw amount.
     */
    function updateDesiredDrawAmount(uint256 desiredDrawAmount)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
    {
        _updateDesiredDrawAmount(desiredDrawAmount);
    }

    function _updateDesiredDrawAmount(uint256 desiredDrawAmount) private {
        _poolConfiguration.desiredDrawAmount = desiredDrawAmount;
        emit UpdatedDesiredDrawAmount(desiredDrawAmount);
    }

    /**
     * @notice Updates the target excess liquidity percentage. Used to calculate how much excess liquidity should be accepted based on the user owed amount.
     * @param targetExcessLiquidityPercentage The target excess liquidity percentage.
     */
    function updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
    {
        if (targetExcessLiquidityPercentage < _poolConfiguration.minimumExcessLiquidityPercentage) {
            revert PoolConfigurationIsIncorrect(
                "Target excess liquidity percentage is less than minimum excess liquidity percentage"
            );
        }

        if (targetExcessLiquidityPercentage > FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("Target excess liquidity percentage is more than 100%");
        }

        _poolConfiguration.targetExcessLiquidityPercentage = targetExcessLiquidityPercentage;
    }

    /**
     * @notice Updates the minimum excess liquidity percentage. Used to calculate how much excess liquidity should stay in the lending pool if there are more withdrawals.
     * @param minumumExcessLiquidityPercentage The minimum excess liquidity percentage.
     */
    function updateMinimumExcessLiquidityPercentage(uint256 minumumExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
        lendingPoolShouldNotBeStopped
    {
        if (minumumExcessLiquidityPercentage > _poolConfiguration.targetExcessLiquidityPercentage) {
            revert PoolConfigurationIsIncorrect(
                "Minimum excess liquidity percentage is more than target excess liquidity percentage"
            );
        }

        _poolConfiguration.minimumExcessLiquidityPercentage = minumumExcessLiquidityPercentage;
    }

    // functions to handle the delay of interest rates

    function _getTrancheInterestRateIndex(address tranche, uint256 epoch) private view returns (uint256 index) {
        index = _trancheInterestIndex[tranche];

        for (uint256 i = index + 1; i < _futureTrancheInterests[tranche].length; ++i) {
            if (_futureTrancheInterests[tranche][i].epoch <= epoch) {
                index++;
            } else {
                break;
            }
        }
    }

    function _getTrancheInterestRate(address tranche, uint256 epoch) private view returns (uint256 interestRate) {
        uint256 index = _getTrancheInterestRateIndex(tranche, epoch);
        interestRate = _futureTrancheInterests[tranche][index].interestRate;
    }

    function _updateTrancheInterestRateConfig(uint256 epoch) private {
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            address tranche = _lendingPoolInfo.trancheAddresses[i];
            uint256 index = _getTrancheInterestRateIndex(tranche, epoch);
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

    // Helper functions

    function _verifyPoolConfiguration() private view {
        // verify addresses
        AddressLib.checkIfZero(_poolConfiguration.drawRecipient);

        uint256 maxTrancheInterestRate = systemVariables.maxTrancheInterestRate();

        // verify tranche: number of tranches, interest rates,  ratios, maxDepositAmount

        if (_poolConfiguration.tranches.length < systemVariables.minTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count less than minimum");
        }

        if (_poolConfiguration.tranches.length > systemVariables.maxTrancheCountPerLendingPool()) {
            revert ILendingPool.PoolConfigurationIsIncorrect("tranche count more than maximum");
        }

        uint256 ratiosSum;
        for (uint256 i; i < _poolConfiguration.tranches.length; ++i) {
            if (_poolConfiguration.tranches[i].interestRate > maxTrancheInterestRate) {
                revert PoolConfigurationIsIncorrect("interest rate is more than max allowed");
            }
            ratiosSum += _poolConfiguration.tranches[i].ratio;
        }
        if (ratiosSum != FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("invalid tranche ratio sum");
        }
    }

    function _onlyPendingPool() private view {
        if (msg.sender != _lendingPoolInfo.pendingPool) {
            revert OnlyOwnPendingPool(msg.sender, _lendingPoolInfo.pendingPool);
        }
    }

    function _onlyLendingPoolManager() private view {
        if (msg.sender != lendingPoolManager) {
            revert OnlyLendingPoolManager();
        }
    }

    function _onlyClearingCoordinator() private view {
        if (msg.sender != address(clearingCoordinator)) {
            revert OnlyClearingCoordinator();
        }
    }

    function _verifyTranche(address tranche) private view {
        if (!isLendingPoolTranche(tranche)) {
            revert InvalidTranche(address(this), tranche);
        }
    }

    function _setTrancheIndex(address tranche, uint256 index) internal {
        _trancheIndex[tranche] = index + 1;
    }

    function _getTrancheConfiguration(address tranche) internal view returns (TrancheConfig storage) {
        return _poolConfiguration.tranches[getTrancheIndex(tranche)];
    }

    function _isLossIdValid(uint256 lossId) internal view {
        if (lossId >= nextLossId || lossId == 0) {
            revert LossIdNotValid(lossId);
        }
    }

    function _verifyClearingNotPending() private view {
        if (clearingCoordinator.isLendingPoolClearingPending(address(this))) {
            revert ClearingIsPending();
        }
    }

    // Modifiers

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
}
