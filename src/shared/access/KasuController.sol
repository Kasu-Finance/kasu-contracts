// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import "../interfaces/IKasuController.sol";
import "./Roles.sol";

/**
 * @notice Kasu access control management
 */
contract KasuController is AccessControlUpgradeable, IKasuController {
    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function hasLendingPoolRole(address lendingPool, bytes32 role, address account) external view returns (bool) {
        return hasRole(_getLendingPoolRole(lendingPool, role), account);
    }

    function checkIsAdminOrVaultAdmin(address lendingPool, address account) external view {
        _onlyAdminOrVaultAdmin(lendingPool, account);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function grantLendingPoolRole(address lendingPool, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(lendingPool, msg.sender)
    {
        _grantRole(_getLendingPoolRole(lendingPool, role), account);
        emit LendingPoolRoleGranted(lendingPool, role, account);
    }

    function revokeLendingPoolRole(address lendingPool, bytes32 role, address account)
        external
        onlyAdminOrVaultAdmin(lendingPool, msg.sender)
    {
        _revokeRole(_getLendingPoolRole(lendingPool, role), account);
        emit LendingPoolRoleRevoked(lendingPool, role, account);
    }

    function renounceLendingPoolRole(address lendingPool, bytes32 role) external {
        renounceRole(_getLendingPoolRole(lendingPool, role), msg.sender);
        emit LendingPoolRoleRenounced(lendingPool, role, msg.sender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _onlyAdminOrVaultAdmin(address lendingPool, address account) private view {
        bytes32 vaultAdminRole = _getLendingPoolRole(lendingPool, ROLE_LENDING_POOL_ADMIN);
        if (!hasRole(DEFAULT_ADMIN_ROLE, account) && !hasRole(vaultAdminRole, account)) {
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

    modifier onlyAdminOrVaultAdmin(address lendingPool, address account) {
        _onlyAdminOrVaultAdmin(lendingPool, account);
        _;
    }
}
