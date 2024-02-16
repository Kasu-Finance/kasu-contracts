// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../../shared/CommonErrors.sol";
import "./LendingPoolHelpers.sol";

/**
 * @dev
 * - when deposits are cleared, users receive ERC20 receipt tranche tokens
 * - when withdrawals are cleared, assets are sent to the lending pool
 * - when impairment happens, users receive ERC1155 impairment receipt tokens
 */
contract LendingPoolTranche is
    ILendingPoolTranche,
    ERC4626Upgradeable,
    ERC1155Upgradeable,
    ILendingPoolErrors,
    LendingPoolHelpers
{
    mapping(address => bool) private isTrancheUser;

    address[] private trancheUsers;

    constructor(ILendingPoolManager lendingPoolManager_) LendingPoolHelpers(lendingPoolManager_) {}

    /**
     * @param name_ The name of the lending pool tranche token
     * @param symbol_ The symbol of the lending pool tranche token
     * @param lendingPool_ Lending pool address
     */
    function initialize(string memory name_, string memory symbol_, ILendingPool lendingPool_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(lendingPool_);
        __ERC1155_init("");
        __LendingPoolHelpers_init(lendingPool_);
    }

    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        returns (uint256)
    {
        if (isTrancheUser[receiver] == false) {
            isTrancheUser[receiver] = true;
            trancheUsers.push(receiver);
        }

        return super.deposit(assets, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        returns (uint256)
    {
        // NOTE: make sure the shares are not pending withdrawal or possibly lick the pending withdrawal amount
        if (balanceOf(receiver) == 0) {
            isTrancheUser[receiver] = false;
            // TODO: remove from the array
            // maybe by adding an id to each user in the trancheUsers array
        }

        return super.redeem(shares, receiver, owner);
    }

    function reportTrancheLoss(uint256 lossAmount) external view onlyOwnLendingPool returns (uint256 lossApplied) {
        uint256 totalAssets_ = totalAssets();
        if (totalAssets_ > 0) {
            // check if total assets can cover the loss
            if (totalAssets_ >= lossAmount) {
                lossApplied = lossAmount;
            } else {
                lossApplied = totalAssets_;
            }

            // TODO: mint loss tokens to all users

            unchecked {
                totalAssets_ -= lossApplied;
            }

            // TODO: if tranche assets are 0, then burn all share tokens
            if (totalAssets_ == 0) {
                // burn all shares from all users
            }
        }
    }

    function withdraw(uint256, address, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert NotSupported();
    }

    function mint(uint256, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert NotSupported();
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal override {
        if (spender == _getPendingPool()) return;
        if (spender == address(_getOwnLendingPool())) return;
        super._spendAllowance(owner, spender, value);
    }

    function transfer(address to, uint256 value) public override(IERC20, ERC20Upgradeable) returns (bool) {
        if (to != _getPendingPool() && msg.sender != _getPendingPool()) {
            revert NonTransferable();
        }
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        returns (bool)
    {
        if (to != _getPendingPool() && from != _getPendingPool()) {
            revert NonTransferable();
        }
        return super.transferFrom(from, to, value);
    }
}
