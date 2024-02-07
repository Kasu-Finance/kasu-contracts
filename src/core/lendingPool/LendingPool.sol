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
import "../../shared/Stoppable.sol";

/**
 * @dev
 * This contract is the ledger of the lending pool balances.
 * The lending pool is also a ERC20 token. This token always represents
 * the total balance of the lending pool against the underlying asset.
 */
contract LendingPool is ILendingPool, ERC20Upgradeable, AssetFunctionsBase, ILendingPoolErrors, Stoppable {
    ISystemVariables public immutable systemVariables;

    /// @dev Lending pool configuration.
    LendingPoolInfo private _lendingPoolInfo;
    /// @notice Is the address a lending pool tranche.
    mapping(address => bool) public isTranche;

    uint256 public borrowedAmount;
    address public borrowRecipient;
    address public lendingPoolManager;
    uint256 public firstLossCapital;

    constructor(ISystemVariables systemVariables_, address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {
        systemVariables = systemVariables_;
    }

    /**
     * @notice Initializes the lending pool.
     * @param poolConfiguration_ Lending pool configuration.
     * @param lendingPoolInfo_ Lending pool info containing other addresses and configuration.
     */
    function initialize(
        PoolConfiguration memory poolConfiguration_,
        LendingPoolInfo memory lendingPoolInfo_,
        address lendingPoolManager_
    ) public initializer {
        if (lendingPoolManager_ == address(0)) {
            revert ConfigurationAddressZero();
        }

        if (poolConfiguration_.borrowRecipient == address(0)) {
            revert ConfigurationAddressZero();
        }

        __ERC20_init(poolConfiguration_.name, poolConfiguration_.symbol);

        // TODO: setup the lending pool and it's tranches
        _lendingPoolInfo.pendingPool = lendingPoolInfo_.pendingPool;

        for (uint256 i; i < lendingPoolInfo_.tranches.length; i++) {
            _lendingPoolInfo.tranches.push(lendingPoolInfo_.tranches[i]);
            address tranche = lendingPoolInfo_.tranches[i].trancheAddress;
            isTranche[tranche] = true;

            _approve(address(this), tranche, type(uint256).max);
        }

        borrowRecipient = poolConfiguration_.borrowRecipient;
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

    /**
     * @notice Returns the pending pool address.
     * @return The pending pool address.
     */
    function getPendingPool() public view returns (address) {
        return _lendingPoolInfo.pendingPool;
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
        shouldNotBeStopped
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
    function borrowLoan(uint256 borrowAmount) external shouldNotBeStopped onlyLendingPoolManager {
        if (borrowAmount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }

        uint256 availableAmount = underlyingAsset.balanceOf(address(this));
        if (availableAmount < borrowAmount) {
            revert BorrowAmountCantBeGreaterThanAvailableAmount(borrowAmount, availableAmount);
        }

        borrowedAmount += borrowAmount;
        _transferAssets(borrowRecipient, borrowAmount);

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
     * @return lossId The id of the loss.
     */
    function reportLoss(uint256 lossAmount) external returns (uint256 lossId) {
        // verify caller

        // verify input
        if (lossAmount > 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than total balance
        // TODO: the amount should not be greater than the borrowed amount (less than total balance)
        if (lossAmount > borrowedAmount) {
            revert LossAmountCantBeGreaterThanSupply(lossAmount, borrowedAmount);
        }

        borrowedAmount -= lossAmount;

        // get the loss id
        lossId = 0;

        // TODO: remove the amount from the first loss capital

        // remove the funds from the tranches and mint loss tokens if first loss capital is not enough
        for (uint256 i; i < _lendingPoolInfo.tranches.length; ++i) {
            if (lossAmount > 0) {
                uint256 lossApplied =
                    ILendingPoolTranche(_lendingPoolInfo.tranches[i].trancheAddress).reportTrancheLoss(lossAmount);
                _burn(_lendingPoolInfo.tranches[i].trancheAddress, lossApplied);

                lossAmount -= lossApplied;
            } else {
                break;
            }
        }

        emit LossReported(lossAmount);
    }

    function depositFirstLossCapital(uint256 amount) external shouldNotBeStopped onlyLendingPoolManager {
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

        emit ImmediateWithdrawalForces(user, tranche, sharesToWithdraw, assetAmount);
    }

    function stop(address firstLossCapitalReceiver) external onlyLendingPoolManager {
        if (borrowedAmount > 0) {
            revert BorrowedAmountIsGreaterThnZero(borrowedAmount);
        }

        if (firstLossCapital > 0) {
            _withdrawFirstLossCapital(firstLossCapital, firstLossCapitalReceiver);
        }

        IPendingPool(getPendingPool()).stop();

        _stop();
    }

    // Helper functions

    function _onlyPendingPool() private view {
        if (msg.sender != _lendingPoolInfo.pendingPool) {
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
        if (!isTranche[tranche]) {
            revert InvalidTranche(address(this), tranche);
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

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }
}
