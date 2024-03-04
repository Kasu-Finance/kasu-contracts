// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../../shared/CommonErrors.sol";
import "./LendingPoolTrancheLoss.sol";
import "./LendingPoolHelpers.sol";

/**
 * @title Lending Pool Tranche Contract
 * @dev
 * - when deposits are cleared, users receive ERC20 receipt tranche tokens
 * - when withdrawals are cleared, assets are sent to the lending pool
 * - when impairment happens, users receive ERC1155 impairment receipt tokens
 */
contract LendingPoolTranche is ILendingPoolTranche, ERC4626Upgradeable, LendingPoolTrancheLoss, ILendingPoolErrors {
    mapping(address user => uint256 activeShares) private _userActiveShares;
    mapping(address user => uint256 index) private _userArrayIndex;

    address[] private _trancheUsers;

    constructor(ILendingPoolManager lendingPoolManager_, address lossAsset_)
        LendingPoolHelpers(lendingPoolManager_)
        AssetFunctionsBase(lossAsset_)
    {
        _disableInitializers();
    }

    /**
     * @param name_ The name of the lending pool tranche token
     * @param symbol_ The symbol of the lending pool tranche token
     * @param lendingPool_ Lending pool address
     */
    function initialize(string memory name_, string memory symbol_, ILendingPool lendingPool_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(lendingPool_);
        __LendingPoolTrancheLoss__init();
        __LendingPoolHelpers_init(lendingPool_);
    }

    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        NotPendingLossMint
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);

        // if user had not shares before, add to the trancheUsers array
        if (_userActiveShares[receiver] == 0) {
            _userArrayIndex[receiver] = _trancheUsers.length;
            _trancheUsers.push(receiver);
        }

        _userActiveShares[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        NotPendingLossMint
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
    }

    function removeUserActiveShares(address user, uint256 shares) external onlyOwnLendingPool {
        _userActiveShares[user] -= shares;

        // remove user from trancheUsers array if they have no shares
        if (_userActiveShares[user] == 0) {
            // get removing and last user
            uint256 removingUserIndex = _userArrayIndex[user];
            uint256 lastUserIndex = _trancheUsers.length - 1;
            address lastUser = _trancheUsers[lastUserIndex];

            // swap removing user with last user
            _trancheUsers[removingUserIndex] = lastUser;
            _trancheUsers.pop();

            // update last and removing user index
            _userArrayIndex[lastUser] = removingUserIndex;
            delete _userArrayIndex[user];
        }
    }

    function _getUsers() internal view override returns (address[] storage users) {
        return _trancheUsers;
    }

    function _getUserActiveTrancheBalance(address user) internal view override returns (uint256) {
        return _userActiveShares[user];
    }

    function getMaximumLossAmount() public view returns (uint256 maxLossAmount) {
        return _getMaximumLossAmount();
    }

    function _getMaximumLossAmount() internal view override returns (uint256 maxLossAmount) {
        uint256 totalAssets_ = totalAssets();

        if (totalAssets_ > minimumLeftAmountAfterLoss) {
            unchecked {
                maxLossAmount = totalAssets_ - minimumLeftAmountAfterLoss;
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

    function approve(address spender, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyPendingPool
        returns (bool)
    {
        return super.approve(spender, value);
    }

    function transfer(address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyPendingPool
        returns (bool)
    {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyPendingPool
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    modifier onlyPendingPool() {
        if (msg.sender != _getPendingPool()) {
            revert NonTransferable();
        }
        _;
    }
}
