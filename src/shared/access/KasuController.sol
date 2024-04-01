// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "../interfaces/IKasuController.sol";
import "./Roles.sol";

/**
 * @notice Kasu access control management
 */
contract KasuController is AccessControlUpgradeable, PausableUpgradeable, IKasuController {
    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address factory) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROLE_LENDING_POOL_FACTORY, factory);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function hasLendingPoolRole(address lendingPool, bytes32 role, address account) public view returns (bool) {
        return hasRole(_getLendingPoolRole(lendingPool, role), account);
    }

    function checkIsAdminOrVaultAdmin(address lendingPool, address account) external view {
        _onlyAdminOrVaultAdmin(lendingPool, account);
    }

    function paused() public view override(IKasuController, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    function requirePaused() external view {
        _requirePaused();
    }

    function requireNotPaused() external view {
        _requireNotPaused();
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function grantLendingPoolRole(address lendingPool, bytes32 role, address account)
        external
        onlyPoolAdminOrFactory(lendingPool, msg.sender)
    {
        _grantRole(_getLendingPoolRole(lendingPool, role), account);
        emit LendingPoolRoleGranted(lendingPool, role, account);
    }

    function revokeLendingPoolRole(address lendingPool, bytes32 role, address account)
        external
        onlyAdminOrPoolAdmin(lendingPool, msg.sender)
    {
        _revokeRole(_getLendingPoolRole(lendingPool, role), account);
        emit LendingPoolRoleRevoked(lendingPool, role, account);
    }

    function pause() external whenNotPaused checkRole(ROLE_KASU_ADMIN) {
        _pause();
    }

    function unpause() external whenPaused checkRole(ROLE_KASU_ADMIN) {
        _unpause();
    }

    function renounceLendingPoolRole(address lendingPool, bytes32 role)
        external
        onlyAdminOrPoolAdmin(lendingPool, msg.sender)
    {
        renounceRole(_getLendingPoolRole(lendingPool, role), msg.sender);
        emit LendingPoolRoleRenounced(lendingPool, role, msg.sender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlyAdminOrVaultAdmin(address lendingPool, address account) private view {
        bytes32 vaultAdminRole = _getLendingPoolRole(lendingPool, ROLE_POOL_ADMIN);
        if (!hasRole(DEFAULT_ADMIN_ROLE, account) && !hasRole(vaultAdminRole, account)) {
            // TODO: DEFAULT_ADMIN_ROLE not reported
            revert MissingRole(vaultAdminRole, account);
        }
    }

    function _getLendingPoolRole(address lendingPool, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(lendingPool, role));
    }

    function _checkRole(bytes32 role, address account) internal view override {
        if (!hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAdminOrPoolAdmin(address lendingPool, address account) {
        _onlyAdminOrVaultAdmin(lendingPool, account);
        _;
    }

    modifier onlyPoolAdminOrFactory(address lendingPool, address account) {
        if (!hasRole(ROLE_LENDING_POOL_FACTORY, account) && !hasLendingPoolRole(lendingPool, ROLE_POOL_ADMIN, account))
        {
            // TODO: ROLE_LENDING_POOL_FACTORY not reported
            revert MissingRole(ROLE_POOL_ADMIN, account);
        }
        _;
    }

    modifier checkRole(bytes32 role) {
        _checkRole(role);
        _;
    }
}
