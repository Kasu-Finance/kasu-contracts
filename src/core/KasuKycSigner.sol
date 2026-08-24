// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/AddressLib.sol";

/**
 * @title Kasu KYC Signer
 * @notice The address Kasu puts in `KasuAllowList.setNexeraIDSigner`, replacing
 * Compilot's `NexeraIDSignerManager`.
 *
 * @dev This exists so the signing key is not the allow-listed address.
 *
 * `BaseTxAuthDataVerifier` checks KYC signatures with OpenZeppelin's
 * `SignatureChecker.isValidSignatureNow`, which falls back to ERC-1271 when the
 * configured signer is a contract. Compilot relied on exactly that: their signer
 * slot held a manager contract, so they could rotate their key without Kasu
 * touching anything on-chain.
 *
 * A bare EOA in that slot would work too, but every key rotation would then be a
 * `setNexeraIDSigner` transaction on `KasuAllowList` — via the Kasu multisig, on
 * each of the four deployments, and coordinated so no frontend signs against the
 * retired key mid-flight. Holding the key behind this contract turns rotation
 * into one `setSigningKey` call per chain and leaves the allow list untouched.
 *
 * The key itself lives in AWS KMS and never exists in plaintext; this contract
 * only ever sees the address derived from it.
 */
contract KasuKycSigner is IERC1271, KasuAccessControllable {
    /* ========== CONSTANTS ========== */

    /// @dev `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`, per ERC-1271.
    bytes4 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /* ========== STATE ========== */

    /// @notice Address derived from the KMS signing key currently in service.
    address public signingKey;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when the signing key is rotated.
     * @param previousKey Address of the retired key.
     * @param newKey Address of the key now in service.
     */
    event SigningKeyRotated(address indexed previousKey, address indexed newKey);

    /* ========== ERRORS ========== */

    /// @notice Thrown when rotating to the key that is already in service.
    error SigningKeyUnchanged();

    /* ========== CONSTRUCTOR ========== */

    /**
     * @param kasuController_ Kasu access control manager.
     * @param signingKey_ Address derived from the initial KMS signing key.
     */
    constructor(IKasuController kasuController_, address signingKey_) KasuAccessControllable(kasuController_) {
        AddressLib.checkIfZero(signingKey_);

        signingKey = signingKey_;
        emit SigningKeyRotated(address(0), signingKey_);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Rotates the signing key.
     * @dev Can only be called by the admin. Takes effect for the next signature
     * verified — signatures already minted against the previous key stop being
     * accepted the moment this lands, so drain the in-flight window (it is
     * bounded by `blockExpiration`) before calling.
     * @param signingKey_ Address derived from the new KMS signing key.
     */
    function setSigningKey(address signingKey_) external onlyAdmin {
        AddressLib.checkIfZero(signingKey_);

        address previousKey = signingKey;
        if (previousKey == signingKey_) {
            revert SigningKeyUnchanged();
        }

        signingKey = signingKey_;
        emit SigningKeyRotated(previousKey, signingKey_);
    }

    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    /**
     * @notice ERC-1271 signature check, called by `SignatureChecker` inside
     * `BaseTxAuthDataVerifier._verifyTxAuthData`.
     * @dev Returns the magic value only for a well-formed signature recovering to
     * the current signing key. `ECDSA.tryRecover` is used rather than `recover`
     * so a malformed or malleable signature returns a plain failure instead of
     * reverting: `isValidSignatureNow` treats a revert as "not valid" anyway, and
     * a clean `bytes4(0)` keeps the failure legible on the allow list side, where
     * it surfaces as `InvalidSignature`.
     *
     * `tryRecover` also rejects high-`s` signatures, so the malleable twin of a
     * valid signature is not itself valid here. That is defence in depth rather
     * than a live concern — the KYC nonce in the signed payload already makes a
     * replayed signature useless.
     *
     * @param hash Digest that was signed (EIP-191 prefixed by the verifier).
     * @param signature 65-byte `(r, s, v)` signature.
     * @return magicValue `0x1626ba7e` when valid, `bytes4(0)` otherwise.
     */
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue) {
        (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(hash, signature);

        if (error == ECDSA.RecoverError.NoError && recovered == signingKey) {
            return _ERC1271_MAGIC_VALUE;
        }

        return bytes4(0);
    }
}
