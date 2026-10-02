// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../interfaces/IUserManager.sol";
import "./LendingPoolTrancheLoss.sol";
import "./LendingPoolHelpers.sol";
import "../../shared/CommonErrors.sol";

/**
 * @title Lending Pool Tranche Contract
 * @notice Lending pool tranche tracks users' position in the tranche.
 * @dev This contract implements ERC4626 and ERC1155.
 * ERC4626 is used to track user tranche shares.
 * Asset of ERC4626 is the lending pool token.
 * ERC1155 is used to track unrealized loss receipt tokens.
 * When deposits are cleared and accepted, users receive ERC20 receipt tranche tokens.
 * When withdrawals are cleared and accepted, assets are sent to the lending pool.
 * When a loss is reported, users receive new ERC1155 unrealized loss receipt tokens.
 * None of the tokens can be transferred by anyone except the lending pool and the pending pool.
 */
contract LendingPoolTranche is ILendingPoolTranche, ERC4626Upgradeable, LendingPoolTrancheLoss {
    /// @notice User manager contract.
    IUserManager private immutable _userManager;
    /// @notice Fixed term deposit address.
    address private immutable _fixedTermDeposit;

    /// @dev User active shares. This includes user pending withdrawal shares.
    mapping(address user => uint256 activeShares) public userActiveShares;
    /// @dev Index of a user in the _trancheUsers array.
    mapping(address user => uint256 index) private _userArrayIndex;
    /// @dev Array of users with active tranche shares.
    address[] private _trancheUsers;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the lending pool tranche contract.
     * @param userManager_ User manager address.
     * @param fixedTermDeposit_ Fixed term deposit address.
     * @param lendingPoolManager_ Lending pool manager address.
     * @param lossAsset_ Loss repayment asset address.
     */
    constructor(
        IUserManager userManager_,
        address fixedTermDeposit_,
        ILendingPoolManager lendingPoolManager_,
        address lossAsset_
    ) LendingPoolHelpers(lendingPoolManager_) AssetFunctionsBase(lossAsset_) {
        _userManager = userManager_;
        _fixedTermDeposit = fixedTermDeposit_;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

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

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the active assets of a user.
     * @dev This value includes pending withdrawals.
     * @param user The address of the user.
     * @return userActiveAssets The active assets of the user.
     */
    function userActiveAssets(address user) external view returns (uint256) {
        return convertToAssets(userActiveShares[user]);
    }

    /**
     * @notice Returns the maximum amount of assets that can be reported as a loss.
     * @return maxLossAmount The maximum amount of assets that can be reported as a loss.
     */
    function calculateMaximumLossAmount() public view returns (uint256) {
        return _calculateMaximumLossAmount();
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Remove user active shares after redeem was called.
     * @dev Lending pool should call this function right after redeem.
     * If user has no shares left, they are removed from the trancheUsers array
     * and the userManager is updated.
     * A zero-share call is a no-op: a user can only leave the tranche when their shares go from non-zero to zero.
     * Without this guard, a zero-share redeem for a user holding no shares (e.g. `forceImmediateWithdrawal` with 0)
     * decremented the user's active tranche count a second time and evicted whichever user sat at index 0.
     * @param user The address of the user.
     * @param shares The amount of shares that were redeemed.
     */
    function removeUserActiveShares(address user, uint256 shares) external onlyOwnLendingPool {
        if (shares == 0) return;

        userActiveShares[user] -= shares;

        // remove user from trancheUsers array if they have no shares
        if (userActiveShares[user] == 0) {
            uint256 removingUserIndex = _userArrayIndex[user];

            if (removingUserIndex < _trancheUsers.length && _trancheUsers[removingUserIndex] == user) {
                // swap removing user with last user
                uint256 lastUserIndex = _trancheUsers.length - 1;
                address lastUser = _trancheUsers[lastUserIndex];

                _trancheUsers[removingUserIndex] = lastUser;
                _trancheUsers.pop();

                // update last and removing user index
                _userArrayIndex[lastUser] = removingUserIndex;
            } else {
                // the user is not where the index says (earlier desync): never evict someone else
                emit TrancheUserIndexMismatch(user, removingUserIndex);
            }
            delete _userArrayIndex[user];

            _userManager.removeUserActiveTranche(user, address(_ownLendingPool()));
        }
    }

    /**
     * @notice Re-adds a user who holds active shares but is missing from the tranche users array.
     * @dev Repairs arrays desynced by the former zero-share removal, which evicted the user at index 0.
     * A missing user receives no loss receipt tokens when a loss is registered.
     * Permissionless and idempotent: every user in the array is at its recorded index (swap-and-pop keeps
     * the index of the moved user), so a user not at its recorded index is absent and is added exactly once.
     * @param user The address of the user.
     */
    function syncTrancheUser(address user) external notPendingLossMint {
        if (userActiveShares[user] == 0) return;

        uint256 index = _userArrayIndex[user];
        if (index < _trancheUsers.length && _trancheUsers[index] == user) return;

        index = _trancheUsers.length;
        _userArrayIndex[user] = index;
        _trancheUsers.push(user);

        emit TrancheUserRestored(user, index);
    }

    /**
     * @notice Deposits assets to the lending pool tranche.
     * @dev Overrides the ERC4626 deposit function.
     * Only the lending pool can call this function.
     * The user receives tranche shares.
     * If the user had no shares before, they are added to the trancheUsers array
     * and the userManager is updated.
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

        // if user had not shares before, add to the trancheUsers array (a zero-share deposit adds nothing)
        if (shares > 0 && userActiveShares[receiver] == 0) {
            _userArrayIndex[receiver] = _trancheUsers.length;
            _trancheUsers.push(receiver);

            _userManager.addUserActiveTranche(receiver, address(_ownLendingPool()));
        }

        userActiveShares[receiver] += shares;
    }

    /**
     * @notice Redeems assets from the lending pool tranche.
     * @dev Overrides the ERC4626 redeem function.
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
     * @notice Transfers the given amount to the given address.
     * @dev Only the pending pool, lending pool or fixed term deposit contract can call this function.
     * @param to The address of the receiver.
     * @param value The amount to transfer.
     * @return success Whether the transfer was successful.
     */
    function transfer(address to, uint256 value) public override(IERC20, ERC20Upgradeable) onlyAllowed returns (bool) {
        return super.transfer(to, value);
    }

    /**
     * @notice Transfers the given amount from the given address to the given address.
     * @dev Only the pending pool, lending pool or fixed term deposit contract can call this function.
     * @param from The address of the sender.
     * @param to The address of the receiver.
     * @param value The amount to transfer.
     * @return success Whether the transfer was successful.
     */
    function transferFrom(address from, address to, uint256 value)
        public
        override(IERC20, ERC20Upgradeable)
        onlyAllowed
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

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

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _trancheUsersStorage() internal view override returns (address[] storage) {
        return _trancheUsers;
    }

    function _userActiveTrancheBalance(address user) internal view override returns (uint256) {
        return userActiveShares[user];
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

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows all spending for the lending pool, pending pool and fixed term deposit.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal override {
        if (spender == _pendingPool()) return;
        if (spender == address(_ownLendingPool())) return;
        if (spender == _fixedTermDeposit) return;
        super._spendAllowance(owner, spender, value);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAllowed() {
        if (msg.sender != _pendingPool() && msg.sender != address(_ownLendingPool()) && msg.sender != _fixedTermDeposit)
        {
            revert NonTransferable();
        }
        _;
    }
}
