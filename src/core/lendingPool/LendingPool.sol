// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/ISystemVariables.sol";
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

    LendingPoolInfo private _lendingPoolInfo;
    PoolConfiguration private _poolConfiguration;
    /// @notice The index of lending pool info and pool configuration
    mapping(address => uint256) private _trancheIndex;

    uint256 public borrowedAmount;
    address public lendingPoolManager;
    uint256 public firstLossCapital;

    constructor(ISystemVariables systemVariables_, address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {
        systemVariables = systemVariables_;
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
    ) public initializer {
        __ERC20_init(createPoolConfig.poolName, createPoolConfig.poolSymbol);

        _lendingPoolInfo.pendingPoolAddress = lendingPoolInfo_.pendingPoolAddress;

        uint256 defaultTrancheInterestChangeEpochDelay = systemVariables.defaultTrancheInterestChangeEpochDelay();

        // copy memory to storage
        _poolConfiguration.targetExcessLiquidity = createPoolConfig.targetExcessLiquidity;
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

            _lendingPoolInfo.trancheAddresses.push(lendingPoolInfo_.trancheAddresses[i]);
            _setTrancheIndex(lendingPoolInfo_.trancheAddresses[i], i);

            _approve(address(this), lendingPoolInfo_.trancheAddresses[i], type(uint256).max);
        }

        _verifyPoolConfiguration();

        lendingPoolManager = lendingPoolManager_;
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

    function poolConfiguration() external returns (PoolConfiguration memory) {
        return _poolConfiguration;
    }

    /**
     * @notice Returns the pending pool address.
     * @return The pending pool address.
     */
    function getPendingPool() public view returns (address) {
        return _lendingPoolInfo.pendingPoolAddress;
    }

    /**
     * @notice Returns the balance of the tranche.
     * @param tranche The tranche address.
     * @return Balance of the tranche in the underlying asset.
     */
    function getTrancheBalance(address tranche) external view verifyTranche(tranche) returns (uint256) {
        return balanceOf(tranche);
    }

    function getUserAvailableBalance(address user) external view returns (uint256 availableBalance) {
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            ILendingPoolTranche tranche = ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]);

            availableBalance += tranche.convertToAssets(tranche.balanceOf(user));
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
    {
        // transfer usdc from pending pool to lending pool - pre-approved
        _transferAssetsFrom(msg.sender, address(this), acceptedAmount);

        // mint lending pool tokens, the same amount as the accepted usdc deposit
        _mint(address(this), acceptedAmount);

        // transfer lending pool tokens from lending pool to the user in tranche - creates tranche shares for user
        ILendingPoolTranche(tranche).deposit(acceptedAmount, user);

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

    function _applyInterest(address tranche) internal verifyTranche(tranche) {
        //        uint256 trancheBalance = balanceOf(tranche);
        //
        //        uint256 yieldAmount = trancheBalance * epochInterestRate / fullPercent;
        //
        //        _mint(tranche, yieldAmount);
        //
        //        borrowedAmount += yieldAmount;
    }

    /**
     * @notice Transfers USDC from lending pool to pool delegate
     * @param borrowAmount the amount that the pool delegate requests
     */
    function borrowLoan(uint256 borrowAmount) external lendingPoolShouldNotBeStopped onlyLendingPoolManager {
        if (borrowAmount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        uint256 availableAmount = underlyingAsset.balanceOf(address(this));
        if (availableAmount < borrowAmount) {
            revert BorrowAmountCantBeGreaterThanAvailableAmount(borrowAmount, availableAmount);
        }

        borrowedAmount += borrowAmount;
        _transferAssets(_poolConfiguration.borrowRecipient, borrowAmount);

        emit LoanBorrowed(borrowAmount);
    }

    function repayLoan(uint256 amount, address repaymentAddress) external onlyLendingPoolManager {
        if (amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        if (amount > borrowedAmount) {
            revert RepayAmountCantBeGreaterThanBorrowedAmount(amount, borrowedAmount);
        }

        _transferAssetsFrom(repaymentAddress, address(this), amount);

        borrowedAmount -= amount;

        emit LoanRepaid(amount);
    }

    /**
     * @notice Reports the loss of the lending pool.
     * @dev
     * Applies the loss first to the first loss capital.
     * If there is no more first loss capital,
     * the loss is applied to the tranches in order from the junior to the senior.
     * Burns tranche shares if needed.
     * Burns the lending pool token.
     * @param lossAmount The amount of the loss.
     * @return appliedLoss The id of the loss.
     */
    function reportLoss(uint256 lossAmount, bool doMintLossShares)
        external
        onlyLendingPoolManager
        returns (uint256 appliedLoss)
    {
        if (systemVariables.isClearingTime()) {
            revert CannotExecuteDuringClearingTime();
        }

        // verify input
        if (lossAmount == 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than total balance
        // TODO: the amount should not be greater than the borrowed amount (less than total balance)
        if (lossAmount > borrowedAmount) {
            revert LossAmountCantBeGreaterThanSupply(lossAmount, borrowedAmount);
        }

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

            emit FirstLossCapitalLossReported(firstLossCapitalLoss);
        }

        // remove the funds from the tranches and mint loss tokens if first loss capital is not enough
        for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            if (lossLeft > 0) {
                uint256 trancheLossApplied = ILendingPoolTranche(_lendingPoolInfo.trancheAddresses[i]).reportTrancheLoss(
                    lossLeft, doMintLossShares
                );

                // lending pool tranche should return tokens
                _burn(address(this), trancheLossApplied);

                lossLeft -= trancheLossApplied;
            } else {
                break;
            }
        }

        appliedLoss = lossAmount - lossLeft;

        borrowedAmount -= appliedLoss;

        emit LossReported(appliedLoss);
    }

    function repayLoss(address tranche, uint256 lossId, uint256 amount)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
    {
        _transferAssetsFrom(msg.sender, address(this), amount);
        _approveAsset(tranche, amount);
        ILendingPoolTranche(tranche).repayLoss(lossId, amount);
    }

    function claimLoss(address user, address tranche, uint256 lossId)
        external
        onlyLendingPoolManager
        verifyTranche(tranche)
        returns (uint256 claimedAmount)
    {
        claimedAmount = ILendingPoolTranche(tranche).claimLoss(user, lossId);
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
        if (borrowedAmount > 0) {
            revert BorrowedAmountIsGreaterThanZero(borrowedAmount);
        }

        if (firstLossCapital > 0) {
            _withdrawFirstLossCapital(firstLossCapital, firstLossCapitalReceiver);
        }

        for (uint256 i = 0; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
            _poolConfiguration.tranches[i].interestRate = 0;
        }
        // TODO: remove desired borrow amount in the future

        IPendingPool(getPendingPool()).stop();

        _stopLendingPool();
    }

    // config

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
        _getTrancheConfiguration(tranche).interestRate = interestRate;
        _verifyPoolConfiguration();
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
            if (_poolConfiguration.tranches[i].interestRate == 0) {
                revert PoolConfigurationIsIncorrect("interest rate is zero");
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
            // TODO: Type Error
            revert("LendingPool: only pending pool");
        }
    }

    function _onlyLendingPoolManager() private view {
        if (msg.sender != lendingPoolManager) {
            // TODO: Type Error
            revert("LendingPool: only lending pool manager");
        }
    }

    function _verifyTranche(address tranche) private view {
        if (_trancheIndex[tranche] == 0) {
            revert InvalidTranche(address(this), tranche);
        }
    }

    function _setTrancheIndex(address tranche, uint256 index) internal {
        _trancheIndex[tranche] = index + 1;
    }

    function _getTrancheConfiguration(address tranche) internal view returns (TrancheConfig storage) {
        return _poolConfiguration.tranches[_trancheIndex[tranche] - 1];
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

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }
}
