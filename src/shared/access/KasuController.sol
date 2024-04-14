// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IKasuController.sol";
import "./Roles.sol";
import "../AddressLib.sol";

/**
 * @notice Kasu access control management
 */
contract KasuController is AccessControlUpgradeable, PausableUpgradeable, IKasuController {
    /* ========== CONSTRUCTOR ========== */

    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(address admin, address factory) public initializer {
        AddressLib.checkIfZero(admin);
        AddressLib.checkIfZero(factory);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ROLE_LENDING_POOL_FACTORY, factory);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function hasLendingPoolRole(address lendingPool, bytes32 role, address account) public view returns (bool) {
        return hasRole(_getLendingPoolRole(lendingPool, role), account);
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

    function renounceLendingPoolRole(address lendingPool, bytes32 role) external {
        renounceRole(_getLendingPoolRole(lendingPool, role), msg.sender);
        emit LendingPoolRoleRenounced(lendingPool, role, msg.sender);
    }

    function pause() external whenNotPaused onlyRole(ROLE_KASU_ADMIN) {
        _pause();
    }

    function unpause() external whenPaused onlyRole(ROLE_KASU_ADMIN) {
        _unpause();
    }

    /* ========== INTERNAL VIEW FUNCTIONS ========== */

    function _onlyAdminOrPoolAdmin(address lendingPool, address account) private view {
        bytes32 poolAdminRole = _getLendingPoolRole(lendingPool, ROLE_POOL_ADMIN);
        if (!hasRole(ROLE_KASU_ADMIN, account) && !hasRole(poolAdminRole, account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, ROLE_POOL_ADMIN);
        }
    }

    function _getLendingPoolRole(address lendingPool, bytes32 role) internal pure returns (bytes32) {
        return keccak256(abi.encode(lendingPool, role));
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAdminOrPoolAdmin(address lendingPool, address account) {
        _onlyAdminOrPoolAdmin(lendingPool, account);
        _;
    }

    modifier onlyPoolAdminOrFactory(address lendingPool, address account) {
        if (!hasRole(ROLE_LENDING_POOL_FACTORY, account) && !hasLendingPoolRole(lendingPool, ROLE_POOL_ADMIN, account))
        {
            revert MissingRole(ROLE_POOL_ADMIN, account);
        }
        _;
    }
}
