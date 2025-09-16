// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../shared/AddressLib.sol";
import "../shared/interfaces/IKasuController.sol";
import "../shared/access/Roles.sol";
import "../shared/access/KasuAccessControllable.sol";

/**
 * @title Kasu Pool External TVL Token (ERC1155 Upgradeable)
 * @notice Tracks external TVL per pool as balances held by this contract itself. This is an off-protocol
 * representation: values are set manually and are not derived from on-chain core Kasu accounting.
 * @dev Only ROLE_POOL_FUNDS_MANAGER for a given pool can mint/burn, and only to/from this contract.
 *      Token id is derived from the pool address as uint256(uint160(pool)). Transfers are disabled.
 */
contract KasuPoolExternalTVL is
    Initializable,
    ERC1155Upgradeable,
    ERC1155SupplyUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155HolderUpgradeable,
    KasuAccessControllable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IKasuController kasuController_) KasuAccessControllable(kasuController_) {
        _disableInitializers();
    }

    function initialize(string memory baseURI_) public initializer {
        __ERC1155_init(baseURI_);
        __ERC1155Supply_init();
        __ERC1155Burnable_init();
        __ERC1155Holder_init();
    }

    /* ========== ERRORS ========== */

    /// @notice Reverted when input arrays have mismatched lengths.
    error LengthMismatch();

    /* ========== EVENTS ========== */

    /// @notice Emitted when the external TVL for a pool is updated.
    event ExternalTVLSet(address indexed pool, uint256 oldAmount, uint256 newAmount);

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /// @notice Computes the token id for a pool address.
    function poolId(address pool) public pure returns (uint256) {
        return uint256(uint160(pool));
    }

    /// @notice Returns the external TVL amount tracked for a pool (balance held by this contract for the pool id).
    function externalTVLOfPool(address pool) public view returns (uint256) {
        return balanceOf(address(this), poolId(pool));
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /// @notice Sets the base URI. Only Kasu admin.
    function setURI(string memory newURI) external onlyAdmin {
        _setURI(newURI);
    }

    /// @notice Increases external TVL for a pool by minting to this contract. Only ROLE_POOL_FUNDS_MANAGER for the pool.
    function mintExternalTVL(address pool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(pool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
    {
        AddressLib.checkIfZero(pool);
        uint256 id = poolId(pool);
        uint256 beforeAmount = externalTVLOfPool(pool);
        _mint(address(this), id, amount, "");
        emit ExternalTVLSet(pool, beforeAmount, beforeAmount + amount);
    }

    /// @notice Decreases external TVL for a pool by burning from this contract. Only ROLE_POOL_FUNDS_MANAGER for the pool.
    function burnExternalTVL(address pool, uint256 amount)
        external
        whenNotPaused
        onlyLendingPoolRole(pool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
    {
        AddressLib.checkIfZero(pool);
        uint256 id = poolId(pool);
        uint256 beforeAmount = externalTVLOfPool(pool);
        _burn(address(this), id, amount);
        emit ExternalTVLSet(pool, beforeAmount, beforeAmount - amount);
    }

    /// @notice Sets external TVL for a pool to a target amount by minting/burning to reach the value.
    /// @dev Only ROLE_POOL_FUNDS_MANAGER for the pool.
    function setExternalTVL(address pool, uint256 targetAmount)
        external
        whenNotPaused
        onlyLendingPoolRole(pool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
    {
        _setExternalTVLInternal(pool, targetAmount);
    }

    /// @notice Batch version of setExternalTVL.
    function setExternalTVLBatch(address[] calldata pools, uint256[] calldata targetAmounts) external whenNotPaused {
        uint256 length = pools.length;
        if (length != targetAmounts.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < length; i++) {
            _checkLendingPoolRole(pools[i], ROLE_POOL_FUNDS_MANAGER, msg.sender);
            _setExternalTVLInternal(pools[i], targetAmounts[i]);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _setExternalTVLInternal(address pool, uint256 targetAmount) internal {
        AddressLib.checkIfZero(pool);
        uint256 id = poolId(pool);
        uint256 current = externalTVLOfPool(pool);
        if (targetAmount > current) {
            _mint(address(this), id, targetAmount - current, "");
        } else if (current > targetAmount) {
            _burn(address(this), id, current - targetAmount);
        }
        emit ExternalTVLSet(pool, current, targetAmount);
    }

    /* ========== INTERNAL OVERRIDES ========== */

    // Prevent transfers to anyone except this contract (i.e., disallow external moves),
    // and to/from address(0) are allowed only via mint/burn flows.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        // Allow mint (from == address(0)) and burn (to == address(0))
        if (from != address(0) && to != address(0)) {
            // Only allow internal accounting between this contract and itself
            // i.e., disallow any transfer where either side is not this contract
            if (from != address(this) || to != address(this)) {
                revert("Transfers disabled");
            }
        }
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC1155HolderUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
