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
contract LendingPoolTranche is ILendingPoolTranche, ERC4626Upgradeable, LendingPoolTrancheLoss {
    /// @dev User active shares. This includes user pending withdrawal shares.
    mapping(address user => uint256 activeShares) public _userActiveShares;
    /// @dev Index of a user in the _trancheUsers array.
    mapping(address user => uint256 index) private _userArrayIndex;
    /// @dev Array of users with active tranche shares.
    address[] private _trancheUsers;

    /**
     * @param lendingPoolManager_ Lending pool manager address.
     * @param lossAsset_ Loss repayment asset address.
     */
    constructor(ILendingPoolManager lendingPoolManager_, address lossAsset_)
        LendingPoolHelpers(lendingPoolManager_)
        AssetFunctionsBase(lossAsset_)
    {
        _disableInitializers();
    }

    /**
     * @notice Initializes the lending pool tranche contract.
     * @param name_ The name of the lending pool tranche token.
     * @param symbol_ The symbol of the lending pool tranche token.
     * @param lendingPool_ Lending pool address.
     */
    function initialize(string memory name_, string memory symbol_, ILendingPool lendingPool_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(lendingPool_);
        __LendingPoolTrancheLoss__init();
        __LendingPoolHelpers_init(lendingPool_);
    }

    /**
     * @notice Deposits assets to the lending pool tranche.
     * @dev
     * Overrides the ERC4626 deposit function.
     * Only the lending pool can call this function.
     * The user receives tranche shares.
     * If the user had no shares before, they are added to the trancheUsers array.
     * @param assets The amount of assets to deposit.
     * @param receiver The receiver address of the tranche shares.
     * @return shares The amount of shares received.
     */
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        notPendingLossMint
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

    /**
     * @notice Redeems assets from the lending pool tranche.
     * @dev
     * Overrides the ERC4626 redeem function.
     * Only the lending pool can call this function.
     * The user receives assets.
     * function removeUserActiveShares with the user address should be called right after redeem.
     * @param shares The amount of shares to redeem.
     * @param receiver The receiver address of the lending pool token. Should be lending pool address.
     * @param owner The owner address of the tranche shares to redeem. Should be pending pool address.
     * @return assets The amount of assets received.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626Upgradeable, IERC4626)
        onlyOwnLendingPool
        notPendingLossMint
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Remove user active shares after redeem was called.
     * @dev
     * Lending pool should call this function right after redeem.
     * If user has no shares left, they are removed from the trancheUsers array.
     * @param user The address of the user.
     * @param shares The amount of shares that were redeemed.
     */
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

    /**
     * @notice Returns the active assets of a user.
     * @dev This value includes pending withdrawals.
     * @param user The address of the user.
     * @return userActiveAssets The active assets of the user.
     */
    function userActiveAssets(address user) external view returns (uint256) {
        return convertToAssets(_userActiveShares[user]);
    }

    function _trancheUsersStorage() internal view override returns (address[] storage) {
        return _trancheUsers;
    }

    function _userActiveTrancheBalance(address user) internal view override returns (uint256) {
        return _userActiveShares[user];
    }

    /**
     * @notice Returns the maximum amount of assets that can be reported as a loss.
     * @return maxLossAmount The maximum amount of assets that can be reported as a loss.
     */
    function calculateMaximumLossAmount() public view returns (uint256) {
        return _calculateMaximumLossAmount();
    }

    function _calculateMaximumLossAmount() internal view override returns (uint256 maxLossAmount) {
        uint256 totalAssets_ = totalAssets();

        if (totalAssets_ > minimumAssetAmountLeftAfterLoss) {
            unchecked {
                maxLossAmount = totalAssets_ - minimumAssetAmountLeftAfterLoss;
            }
        }
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    /**
     * @notice Transfers the given amount to the given address. Can only be called by the pending pool.
     * @param to The address of the receiver.
     * @param value The amount to transfer.
     * @return success Whether the transfer was successful.
     */
    function transfer(address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyPendingPool
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /**
     * @notice Transfers the given amount from the given address to the given address. Can only be called by the pending pool.
     * @param from The address of the sender.
     * @param to The address of the receiver.
     * @param value The amount to transfer.
     * @return success Whether the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyPendingPool
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    /**
     * @dev Allows all spending for the lending pool and the pending pool.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal override {
        if (spender == _pendingPool()) return;
        if (spender == address(_ownLendingPool())) return;
        super._spendAllowance(owner, spender, value);
    }

    // NOT SUPPORTED FUNCTIONS

    /**
     * @notice Not supported function.
     */
    function approve(address, uint256) public pure override(IERC20, ERC20Upgradeable) returns (bool) {
        revert NotSupported();
    }

    /**
     * @notice Not supported function.
     */
    function withdraw(uint256, address, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert NotSupported();
    }

    /**
     * @notice Not supported function.
     */
    function mint(uint256, address) public pure override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        revert NotSupported();
    }

    // MODIFIERS

    modifier onlyPendingPool() {
        if (msg.sender != _pendingPool()) {
            revert NonTransferable();
        }
        _;
    }
}
