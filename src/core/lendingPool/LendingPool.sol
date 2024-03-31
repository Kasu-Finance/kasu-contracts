// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/ISystemVariables.sol";
import "../interfaces/clearing/IClearingCoordinator.sol";
import "../AssetFunctionsBase.sol";
import "../../shared/CommonErrors.sol";
import "../interfaces/lendingPool/ILendingPoolFactory.sol";
import "./LendingPoolStoppable.sol";
import "../Constants.sol";

/**
 * @dev
 * This contract is the ledger of the lending pool balances.
 * The lending pool is also a ERC20 token. This token always represents
 * the total balance of the lending pool against the underlying asset.
 */
contract LendingPool is ILendingPool, ERC20Upgradeable, AssetFunctionsBase, ILendingPoolErrors, LendingPoolStoppable {
    ISystemVariables public immutable systemVariables;
    IClearingCoordinator public immutable clearingCoordinator;

    LendingPoolInfo private _lendingPoolInfo;
    PoolConfiguration private _poolConfiguration;
    /// @notice The index of lending pool info and pool configuration
    mapping(address => uint256) private _trancheIndex;

    uint256 private _feesOwed;
    uint256 private _userOwedAmount;

    struct FutureTrancheInterestRates {
        uint256 epoch;
        uint256 interestRate;
    }

    mapping(address tranche => FutureTrancheInterestRates[]) private _futureTrancheInterests;
    mapping(address tranche => uint256) private _trancheInterestIndex;

    address public lendingPoolManager;
    uint256 public firstLossCapital;
    uint256 public nextLossId;

    constructor(ISystemVariables systemVariables_, IClearingCoordinator clearingCoordinator_, address underlyingAsset_)
        AssetFunctionsBase(underlyingAsset_)
    {
        systemVariables = systemVariables_;
        clearingCoordinator = clearingCoordinator_;
    }

    /**
     * @notice Initializes the lending pool.
     * @param createPoolConfig Create lending pool configuration.
     * @param lendingPoolInfo_ Lending pool info containing other addresses and configuration.
     */
    function initialize(
        CreatePoolConfig memory createPoolConfig,
        LendingPoolInfo memory lendingPoolInfo_,
        address lendingPoolManager_
    ) public initializer returns (PoolConfiguration memory) {
        __ERC20_init(createPoolConfig.poolName, createPoolConfig.poolSymbol);

        _lendingPoolInfo.pendingPoolAddress = lendingPoolInfo_.pendingPoolAddress;

        uint256 defaultTrancheInterestChangeEpochDelay = systemVariables.defaultTrancheInterestChangeEpochDelay();

        // copy memory to storage
        _poolConfiguration.targetExcessLiquidityPercentage = createPoolConfig.targetExcessLiquidityPercentage;
        _poolConfiguration.poolAdmin = createPoolConfig.poolAdmin;
        _poolConfiguration.borrowRecipient = createPoolConfig.borrowRecipient;
        _poolConfiguration.totalDesiredLoanAmount = createPoolConfig.totalDesiredLoanAmount;
        _poolConfiguration.trancheInterestChangeEpochDelay = defaultTrancheInterestChangeEpochDelay;

        for (uint256 i; i < createPoolConfig.tranches.length; ++i) {
            // copy memory to storage
            _poolConfiguration.tranches.push(
                TrancheConfig(
                    createPoolConfig.tranches[i].ratio,
                    createPoolConfig.tranches[i].interestRate,
                    createPoolConfig.tranches[i].minDepositAmount,
                    createPoolConfig.tranches[i].maxDepositAmount
                )
            );

            _futureTrancheInterests[lendingPoolInfo_.trancheAddresses[i]].push(
                FutureTrancheInterestRates({epoch: 0, interestRate: createPoolConfig.tranches[i].interestRate})
            );

            _lendingPoolInfo.trancheAddresses.push(lendingPoolInfo_.trancheAddresses[i]);
            _setTrancheIndex(lendingPoolInfo_.trancheAddresses[i], i);

            _approve(address(this), lendingPoolInfo_.trancheAddresses[i], type(uint256).max);
        }

        _verifyPoolConfiguration();

        lendingPoolManager = lendingPoolManager_;
        nextLossId = 1;

        return _poolConfiguration;
    }

    /**
     * @notice Decimals of the lending pool token.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function lendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    function poolConfiguration() external view returns (PoolConfiguration memory poolConfiguration_) {
        poolConfiguration_ = _poolConfiguration;

        uint256 currentEpoch = systemVariables.getCurrentEpochNumber();
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            poolConfiguration_.tranches[i].interestRate =
                _getTrancheInterestRate(_lendingPoolInfo.trancheAddresses[i], currentEpoch);
        }
    }

    /**
     * @notice Returns the pending pool address.
     * @return The pending pool address.
     */
    function getPendingPool() public view returns (address) {
        return _lendingPoolInfo.pendingPoolAddress;
    }

    function isLendingPoolTranche(address tranche) public view returns (bool) {
        return _trancheIndex[tranche] != 0;
    }

    function getTrancheIndex(address tranche) public view verifyTranche(tranche) returns (uint256) {
        return _trancheIndex[tranche] - 1;
    }

    function getUserOwedAmount() external view returns (uint256) {
        return _userOwedAmount;
    }

    function getFeesOwedAmount() external view returns (uint256) {
        return _feesOwed;
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
        ILendingPoolTranche(tranche).removeUserActiveShares(user, acceptedShares);

        // burn the lending pool token
        _burn(address(this), assetAmount);

        // transfer usdc to the user
        _transferAssets(user, assetAmount);

        emit WithdrawalAccepted(user, tranche, acceptedShares);
    }

    function applyInterests(uint256 epoch) external onlyClearingCoordinator {
        _applyInterests(epoch);
    }

    function _applyInterests(uint256 epoch) internal {
        _updateTrancheInterestRateConfig(epoch);

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _applyTrancheInterest(_lendingPoolInfo.trancheAddresses[i], epoch);
        }
    }

    function _applyTrancheInterest(address tranche, uint256 epoch) internal {
        uint256 trancheAssetBalance = balanceOf(tranche);
        if (trancheAssetBalance == 0) return;

        uint256 interestAmount =
            trancheAssetBalance * _getTrancheConfiguration(tranche).interestRate / INTEREST_RATE_FULL_PERCENT;

        // calculate fees
        uint256 feesAmount = interestAmount * systemVariables.performanceFee() / FULL_PERCENT;

        // decrease by the fee percentage
        interestAmount -= feesAmount;

        // increase owed amount
        _feesOwed += feesAmount;
        _userOwedAmount += interestAmount;

        // mint the lending pool tokens to the lending pool tranche
        _mint(tranche, interestAmount);

        emit InterestApplied(tranche, epoch, interestAmount);
        emit FeesOwedIncreased(epoch, feesAmount);
    }

    /**
     * @notice Transfers USDC from lending pool to pool delegate
     * @param borrowAmount the amount that the pool delegate requests
     */
    function borrowLoanImmediate(uint256 borrowAmount) external lendingPoolShouldNotBeStopped onlyLendingPoolManager {
        if (borrowAmount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }
        _borrowLoan(borrowAmount);
        emit LoanBorrowedImmediate(borrowAmount);
    }

    // TODO: add access control
    function borrowLoan(uint256 borrowAmount) external lendingPoolShouldNotBeStopped {
        if (!systemVariables.isClearingTime()) {
            revert CanOnlyExecuteDuringClearingTime();
        }
        _borrowLoan(borrowAmount);
        emit LoanBorrowed(borrowAmount);
    }

    function _borrowLoan(uint256 borrowAmount) internal {
        if (borrowAmount == 0) return;
        uint256 availableAmount = underlyingAsset.balanceOf(address(this));
        if (availableAmount < borrowAmount) {
            revert BorrowAmountCantBeGreaterThanAvailableAmount(borrowAmount, availableAmount);
        }

        _userOwedAmount += borrowAmount;
        _transferAssets(_poolConfiguration.borrowRecipient, borrowAmount);
    }

    function repayLoan(uint256 amount, address repaymentAddress) external onlyLendingPoolManager {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (amount > _userOwedAmount) {
            revert RepayAmountCantBeGreaterThanBorrowedAmount(amount, _userOwedAmount);
        }

        _transferAssetsFrom(repaymentAddress, address(this), amount);

        // TODO: pay fees first

        unchecked {
            _userOwedAmount -= amount;
        }

        emit LoanRepaid(amount);
    }

    /**
     * @notice Reports the loss of the lending pool.
     * @dev
     * Applies the loss first to the first loss capital.
     * If there is no more first loss capital,
     * the loss is applied to the tranches in order from the junior to the senior.
     * Burns tranche shares if needed.
     * Burns the lending pool token in te amount of the loss.
     * @param lossAmount The amount of the loss.
     * @param doMintLossTokens If true, mints loss tokens to all the users.
     * @return lossId The id of the loss.
     */
    function reportLoss(uint256 lossAmount, bool doMintLossTokens)
        external
        onlyLendingPoolManager
        returns (uint256 lossId)
    {
        if (systemVariables.isClearingTime()) {
            revert CannotExecuteDuringClearingTime();
        }

        // verify input
        if (lossAmount == 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than total balance
        if (lossAmount > _userOwedAmount) {
            revert LossAmountCantBeGreaterThanSupply(lossAmount, _userOwedAmount);
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

    // TODO: cannot be run during clearing time
    function forceImmediateWithdrawal(address tranche, address user, uint256 sharesToWithdraw)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
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

    function stop(address firstLossCapitalReceiver) external onlyLendingPoolManager {
        if (_userOwedAmount > 0) {
            revert BorrowedAmountIsGreaterThanZero(_userOwedAmount);
        }

        if (firstLossCapital > 0) {
            _withdrawFirstLossCapital(firstLossCapital, firstLossCapitalReceiver);
        }

        // TODO: check the clearing was done including paying interests
        // TODO: pay fees

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _poolConfiguration.tranches[i].interestRate = 0;

            address tranche = _lendingPoolInfo.trancheAddresses[i];

            delete _futureTrancheInterests[tranche];
            delete _trancheInterestIndex[tranche];

            _futureTrancheInterests[tranche].push(FutureTrancheInterestRates({epoch: 0, interestRate: 0}));
        }

        _poolConfiguration.totalDesiredLoanAmount = 0;

        IPendingPool(getPendingPool()).stop();

        // TODO: emit event

        _stopLendingPool();
    }

    // config

    function updateBorrowRecipient(address borrowRecipient) external onlyLendingPoolManager {
        _poolConfiguration.borrowRecipient = borrowRecipient;
    }

    function updateMinimumDepositAmount(address tranche, uint256 minimumDepositAmount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _getTrancheConfiguration(tranche).minDepositAmount = minimumDepositAmount;
    }

    function updateMaximumDepositAmount(address tranche, uint256 maximumDepositAmount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _getTrancheConfiguration(tranche).maxDepositAmount = maximumDepositAmount;
    }

    function updateTrancheInterestRate(address tranche, uint256 interestRate)
        external
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

                emit RemovedTracheInterestRateUpdate(tranche, futureTrancheInterest.epoch, i);
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

        // _futureTrancheInterests[tranche].push(
        //     FutureTrancheInterestRates({epoch: applicableEpoch, interestRate: interestRate})
        // );

        emit UpdatedTrancheInterestRate(tranche, applicableEpoch, interestRate);
    }

    function updateTrancheDesiredRatios(uint256[] calldata ratios) external onlyLendingPoolManager {
        if (ratios.length != _lendingPoolInfo.trancheAddresses.length) {
            revert InvalidArrayLength();
        }

        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _getTrancheConfiguration(_lendingPoolInfo.trancheAddresses[i]).ratio = ratios[i];
        }

        _verifyPoolConfiguration();
    }

    function updateTrancheInterestRateChangeEpochDelay(uint256 epochDelay) external onlyLendingPoolManager {
        _poolConfiguration.trancheInterestChangeEpochDelay = epochDelay;
    }

    function updateTotalDesiredLoanAmount(uint256 totalDesiredLoanAmount) external onlyLendingPoolManager {
        _poolConfiguration.totalDesiredLoanAmount = totalDesiredLoanAmount;
    }

    function updateTargetExcessLiquidityPercentage(uint256 targetExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
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

    function updateMinimumExcessLiquidityPercentage(uint256 minumumExcessLiquidityPercentage)
        external
        onlyLendingPoolManager
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
        if (_poolConfiguration.borrowRecipient == address(0)) {
            revert PoolConfigurationIsIncorrect("borrow receipient is zero address");
        }
        if (_poolConfiguration.poolAdmin == address(0)) {
            revert PoolConfigurationIsIncorrect("pool admin is zero address");
        }

        // totalDesiredLoanAmount
        if (_poolConfiguration.totalDesiredLoanAmount == 0) {
            revert PoolConfigurationIsIncorrect("desired loan amount is zero");
        }

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
            if (_poolConfiguration.tranches[i].ratio == 0) {
                revert PoolConfigurationIsIncorrect("ratio is zero");
            }
            if (_poolConfiguration.tranches[i].interestRate > maxTrancheInterestRate) {
                revert PoolConfigurationIsIncorrect("interest rate is more than max allowed");
            }
            if (_poolConfiguration.tranches[i].maxDepositAmount == 0) {
                revert PoolConfigurationIsIncorrect("max deposit amount is zero");
            }
            ratiosSum += _poolConfiguration.tranches[i].ratio;
        }
        if (ratiosSum != FULL_PERCENT) {
            revert PoolConfigurationIsIncorrect("invalid tranche ratio sum");
        }
    }

    function _onlyPendingPool() private view {
        if (msg.sender != _lendingPoolInfo.pendingPoolAddress) {
            revert OnlyOwnPendingPool(msg.sender, _lendingPoolInfo.pendingPoolAddress);
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
}
