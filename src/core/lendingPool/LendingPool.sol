// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../AssetFunctionsBase.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPool is ILendingPool, ERC20Upgradeable, AssetFunctionsBase, ILendingPoolErrors {
    LendingPoolInfo private _lendingPoolInfo;
    mapping(address => bool) public isTranche;

    constructor(address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {}

    function initialize(string memory name_, string memory symbol_, LendingPoolInfo memory lendingPoolInfo_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);

        // TODO: setup the lending pool and it's tranches
        _lendingPoolInfo.pendingPool = lendingPoolInfo_.pendingPool;

        for (uint256 i; i < lendingPoolInfo_.tranches.length; i++) {
            _lendingPoolInfo.tranches.push(lendingPoolInfo_.tranches[i]);
            address tranche = lendingPoolInfo_.tranches[i].trancheAddress;
            isTranche[tranche] = true;

            _approve(address(this), tranche, type(uint256).max);
        }
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function lendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    function getPendingPool() external view returns (address) {
        return _lendingPoolInfo.pendingPool;
    }

    function getTrancheBalance(address tranche) external view verifyTranche(tranche) returns (uint256) {
        return balanceOf(tranche);
    }

    function acceptDeposit(address tranche, address user, uint256 acceptedAmount)
        external
        onlyPendingPool
        verifyTranche(tranche)
    {
        _transferAssetsFrom(msg.sender, address(this), acceptedAmount);

        // mint the same amount as the accepted deposit
        _mint(address(this), acceptedAmount);

        // deposit the minted tokens to the tranche
        ILendingPoolTranche(tranche).deposit(acceptedAmount, user);
    }

    function acceptWithdrawal(address tranche, address user, uint256 acceptedShares)
        external
        onlyPendingPool
        verifyTranche(tranche)
    {
        // deposit the minted tokens to the tranche
        uint256 lendingPoolToken = ILendingPoolTranche(tranche).redeem(acceptedShares, address(this), address(this));

        // transfer assets to the user
        _transferAssets(user, lendingPoolToken);

        // burn the lending pool token
        _burn(address(this), lendingPoolToken);
    }

    function reportLoss(uint256 lossAmount) external returns (uint256 lossId) {
        // verify caller

        // verify input
        if (lossAmount > 0) {
            revert LossAmountShouldBeGreaterThanZero(lossAmount);
        }

        // verify the amount is not greater than total balance
        if (lossAmount > totalSupply()) {
            revert LossAmountCantBeGreaterThanSupply(lossAmount, totalSupply());
        }

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
    }

    function _onlyPendingPool() private view {
        if (msg.sender != _lendingPoolInfo.pendingPool) {
            revert("LendingPool: only pending pool");
        }
    }

    function _verifyTranche(address tranche) private view {
        if (!isTranche[tranche]) {
            revert InvalidTranche(address(this), tranche);
        }
    }

    modifier onlyPendingPool() {
        _onlyPendingPool();
        _;
    }

    modifier verifyTranche(address tranche) {
        _verifyTranche(tranche);
        _;
    }
}
