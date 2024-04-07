// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../shared/access/KasuAccessControllable.sol";
import "./interfaces/IKasuAllowList.sol";
import "../../vendor/nexeraID/TxAuthDataVerifierUpgradeable.sol";
import "./interfaces/lendingPool/ILendingPoolErrors.sol";
import "../shared/AddressLib.sol";

/**
 * @title Kasu Allow List Contract
 * @notice This contract is used to verify if users are allowed to interact with the protocol.
 */
contract KasuAllowList is IKasuAllowList, KasuAccessControllable, TxAuthDataVerifierUpgradeable {
    /// @notice Lending Pool Manager address.
    address public lendingPoolManager;

    /**
     * @notice Constructor.
     * @param kasuController_ Kasu controller contract.
     */
    constructor(IKasuController kasuController_) KasuAccessControllable(kasuController_) {
        _disableInitializers();
    }

    /// @notice Manual allow list of users.
    mapping(address => bool) public allowList;

    /// @notice Block list of users.
    /// @dev If a user is in the block list, it will be blocked even if it is in the allow list or KYCd.
    mapping(address => bool) public blockList;

    /**
     * @notice Initialize the contract.
     * @param lendingPoolManager_ Lending Pool Manager address.
     * @param signer The address of the user KYC data signer.
     */
    function initialize(address lendingPoolManager_, address signer) public initializer {
        AddressLib.checkIfZero(lendingPoolManager_);
        AddressLib.checkIfZero(signer);

        lendingPoolManager = lendingPoolManager_;
        __TxAuthDataVerifierUpgradeable_init(signer);
    }

    /**
     * @notice Sets the Nexera ID signer address.
     * @dev Can only be called by the admin.
     * @param signer The address of the user KYC data signer.
     */
    function setNexeraIDSigner(address signer) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(signer);
        _setSigner(signer);
    }

    /**
     * @notice Manually allow a user to interact with the protocol.
     * @dev Can only be called by the admin.
     * @param user The user's address.
     */
    function allowUser(address user) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(user);

        if (!allowList[user]) {
            allowList[user] = true;
            emit IKasuAllowList.UserAddedInAllowList(user);
        }
    }

    /**
     * @notice Remove allowance of a user to interact with the protocol.
     * @dev Can only be called by the admin.
     * @param user The user's address.
     */
    function disallowUser(address user) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(user);

        if (allowList[user]) {
            allowList[user] = false;
            emit IKasuAllowList.UserRemovedFromAllowList(user);
        }
    }

    /**
     * @notice Block a user from interacting with the protocol.
     * @dev
     * If blocked, the user will not be able to interact with the protocol even if it is in the allow list or KYCd.
     * Can only be called by the admin.
     * @param user The user's address.
     */
    function blockUser(address user) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(user);

        if (!blockList[user]) {
            blockList[user] = true;
            emit IKasuAllowList.UserBlockedFromAllowList(user);
        }
    }

    /**
     * @notice Remove user from a block list.
     * @dev Can only be called by the admin.
     * @param user The user's address.
     */
    function unblockUser(address user) external whenNotPaused onlyAdmin {
        AddressLib.checkIfZero(user);

        if (blockList[user]) {
            blockList[user] = false;
            emit IKasuAllowList.UserUnblockedFromAllowList(user);
        }
    }

    /**
     * @notice Verifies the user's KYC status via Nexera ID.
     * @dev Can only be called by the Lending Pool Manager as verifying increments the nonce of the user.
     * @param user The user's address.
     * @param blockExpiration The block number after which the kyc signature is considered expired.
     * @param signature The signature of the user's KYC status.
     * @return A boolean indicating whether the user KYC is verified.
     */
    function verifyUserKyc(address user, uint256 blockExpiration, bytes calldata signature) external returns (bool) {
        if (msg.sender != lendingPoolManager) {
            revert ILendingPoolErrors.OnlyLendingPoolManager();
        }

        return _verifyTxAuthData(_msgData(), user, blockExpiration, signature);
    }
}
