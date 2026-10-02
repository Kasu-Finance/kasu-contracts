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
     * @notice Whether the user is in the tranche users array (receives loss receipt tokens).
     * @param user The address of the user.
     * @return True if the user is listed.
     */
    function isTrancheUser(address user) external view returns (bool) {
        return _isTrancheUser(user);
    }

    /**
     * @notice Number of users in the tranche users array.
     * @return The number of listed users.
     */
    function trancheUserCount() external view returns (uint256) {
        return _trancheUsers.length;
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
     * removed the user a second time and evicted whichever user sat at index 0.
     * @param user The address of the user.
     * @param shares The amount of shares that were redeemed.
     */
    function removeUserActiveShares(address user, uint256 shares) external onlyOwnLendingPool {
        if (shares == 0) return;

        userActiveShares[user] -= shares;

        if (userActiveShares[user] == 0) {
            if (_isTrancheUser(user)) {
                _removeTrancheUser(user);
            } else {
                // missing from the array (earlier desync): never evict someone else
                emit TrancheUserNotInArray(user);
            }

            _userManager.removeUserActiveTranche(user, address(_ownLendingPool()));
        } else {
            // still a holder: heal a missing listing or record on this interaction (both idempotent)
            if (!_isTrancheUser(user)) {
                _addTrancheUser(user);
                emit TrancheUserRestored(user, _userArrayIndex[user]);
            }
            _userManager.addUserActiveTranche(user, address(_ownLendingPool()));
        }
    }

    /**
     * @notice Re-derives the user's membership of the tranche users array, and the user's active flag in the
     * user manager, from `userActiveShares`.
     * @dev Adds a holder missing from the array (the former zero-share removal evicted the user at index 0, and
     * a missing user receives no loss receipt tokens), and removes a listed user holding no shares.
     * Permissionless and idempotent: membership is decided by `_isTrancheUser`, the same check every path uses,
     * so a user can never be listed twice.
     * @param user The address of the user.
     */
    function syncTrancheUser(address user) external notPendingLossMint {
        bool isHolder = userActiveShares[user] > 0;
        bool isListed = _isTrancheUser(user);

        if (isHolder && !isListed) {
            _addTrancheUser(user);
            emit TrancheUserRestored(user, _userArrayIndex[user]);
        } else if (!isHolder && isListed) {
            _removeTrancheUser(user);
            emit TrancheUserRemoved(user);
        }

        _userManager.syncUserActiveTrancheFromTranche(user, address(_ownLendingPool()), isHolder);
    }

    /**
     * @notice Deposits assets to the lending pool tranche.
     * @dev Overrides the ERC4626 deposit function.
     * Only the lending pool can call this function.
     * The user receives tranche shares.
     * If the user is not listed, they are added to the trancheUsers array. The userManager record is ensured on
     * every deposit (idempotent), so a missing record heals on the user's next deposit.
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

        // a zero-share deposit changes nothing
        if (shares == 0) return shares;

        if (!_isTrancheUser(receiver)) {
            _addTrancheUser(receiver);
        }

        userActiveShares[receiver] += shares;

        // idempotent: records a first deposit, and heals a missing record on any later one
        _userManager.addUserActiveTranche(receiver, address(_ownLendingPool()));
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

    /// @dev The one membership check: a user is listed iff the slot at its recorded index holds it.
    function _isTrancheUser(address user) private view returns (bool) {
        uint256 index = _userArrayIndex[user];
        return index < _trancheUsers.length && _trancheUsers[index] == user;
    }

    function _addTrancheUser(address user) private {
        _userArrayIndex[user] = _trancheUsers.length;
        _trancheUsers.push(user);
    }

    /// @dev Swap-and-pop. Callers ensure `_isTrancheUser(user)`.
    function _removeTrancheUser(address user) private {
        uint256 removingUserIndex = _userArrayIndex[user];
        address lastUser = _trancheUsers[_trancheUsers.length - 1];

        _trancheUsers[removingUserIndex] = lastUser;
        _trancheUsers.pop();

        _userArrayIndex[lastUser] = removingUserIndex;
        delete _userArrayIndex[user];
    }

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
