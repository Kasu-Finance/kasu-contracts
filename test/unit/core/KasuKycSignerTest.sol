// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../_utils/BaseTestUtils.sol";
import "../../../src/core/KasuAllowList.sol";
import "../../../src/core/KasuKycSigner.sol";

/**
 * @notice Covers `KasuKycSigner` through the real `KasuAllowList.verifyUserKyc`
 * path rather than by calling `isValidSignature` directly.
 *
 * The whole point of this contract is that `SignatureChecker` inside
 * `BaseTxAuthDataVerifier` takes the ERC-1271 branch when the signer slot holds a
 * contract. Testing `isValidSignature` in isolation would pass even if that
 * branch were never reached, which is the one failure that matters: it would take
 * the deposit gate down on all four chains the moment the signer is rotated.
 */
contract KasuKycSignerTest is BaseTestUtils {
    address internal _lendingPoolManager = address(0x11);

    uint256 internal kmsKeyPrivate = 0xA11CE;
    uint256 internal rotatedKeyPrivate = 0xB0B;
    uint256 internal attackerKeyPrivate = 0xBAD;

    address internal kmsKey = vm.addr(kmsKeyPrivate);
    address internal rotatedKey = vm.addr(rotatedKeyPrivate);

    KasuAllowList internal kasuAllowList;
    KasuKycSigner internal kycSigner;
    IKasuController internal kasuController = IKasuController(address(0xcccc));

    function setUp() public {
        vm.mockCall(address(kasuController), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));
        vm.mockCall(
            address(kasuController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, ROLE_KASU_ADMIN, admin),
            abi.encode(true)
        );

        kycSigner = new KasuKycSigner(kasuController, kmsKey);

        KasuAllowList impl = new KasuAllowList(kasuController);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), admin, "");
        kasuAllowList = KasuAllowList(address(proxy));

        // The signer slot holds the CONTRACT, not the key — this is the migration.
        kasuAllowList.initialize(_lendingPoolManager, address(kycSigner));
    }

    /* ========== HELPERS ========== */

    /// @dev Mints a KYC signature exactly the way the backend signer service will.
    function _sign(uint256 privateKey, address user, uint256 blockExpiration) internal view returns (bytes memory) {
        BaseTxAuthDataVerifier.TxAuthData memory txAuthData = BaseTxAuthDataVerifier.TxAuthData({
            functionCallData: abi.encodeCall(kasuAllowList.verifyUserKyc, (user)),
            contractAddress: address(kasuAllowList),
            userAddress: user,
            chainID: block.chainid,
            nonce: kasuAllowList.nonces(user),
            blockExpiration: blockExpiration
        });

        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(kasuAllowList.getMessageHash(txAuthData));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Replays what `LendingPoolManager._isUserKycd` builds and calls.
    function _verify(address user, uint256 blockExpiration, bytes memory signature) internal returns (bool) {
        bytes memory callData = bytes.concat(
            abi.encodeCall(kasuAllowList.verifyUserKyc, (user)), abi.encodePacked(blockExpiration, signature)
        );

        vm.prank(_lendingPoolManager);
        (bool ok, bytes memory response) = address(kasuAllowList).call(callData);
        require(ok, "verifyUserKyc reverted");
        return abi.decode(response, (bool));
    }

    /* ========== TESTS ========== */

    function test_verifyUserKyc_acceptsSignatureFromKeyBehindTheContract() public {
        uint256 blockExpiration = block.number + 10;
        bytes memory signature = _sign(kmsKeyPrivate, alice, blockExpiration);

        assertTrue(_verify(alice, blockExpiration, signature));
        // Nonce consumed — the same signature cannot be presented twice.
        assertEq(kasuAllowList.nonces(alice), 1);
    }

    function test_verifyUserKyc_rejectsSignatureFromAnyOtherKey() public {
        uint256 blockExpiration = block.number + 10;
        bytes memory signature = _sign(attackerKeyPrivate, alice, blockExpiration);

        bytes memory callData = bytes.concat(
            abi.encodeCall(kasuAllowList.verifyUserKyc, (alice)), abi.encodePacked(blockExpiration, signature)
        );

        vm.prank(_lendingPoolManager);
        (bool ok,) = address(kasuAllowList).call(callData);
        assertFalse(ok, "a signature from an unknown key must not verify");
    }

    function test_verifyUserKyc_signatureForOneUserDoesNotWorkForAnother() public {
        uint256 blockExpiration = block.number + 10;
        bytes memory aliceSignature = _sign(kmsKeyPrivate, alice, blockExpiration);

        bytes memory callData = bytes.concat(
            abi.encodeCall(kasuAllowList.verifyUserKyc, (bob)), abi.encodePacked(blockExpiration, aliceSignature)
        );

        vm.prank(_lendingPoolManager);
        (bool ok,) = address(kasuAllowList).call(callData);
        assertFalse(ok, "a signature is bound to one user address");
    }

    function test_rotation_newKeyWorksAndOldKeyStopsWorking() public {
        // A signature minted before rotation, still inside its expiry window.
        uint256 blockExpiration = block.number + 10;
        bytes memory oldKeySignature = _sign(kmsKeyPrivate, alice, blockExpiration);

        vm.prank(admin);
        kycSigner.setSigningKey(rotatedKey);

        // The in-flight signature is now dead. This is why rotation needs the
        // expiry window drained first, and why it costs no KasuAllowList tx.
        bytes memory callData = bytes.concat(
            abi.encodeCall(kasuAllowList.verifyUserKyc, (alice)), abi.encodePacked(blockExpiration, oldKeySignature)
        );
        vm.prank(_lendingPoolManager);
        (bool ok,) = address(kasuAllowList).call(callData);
        assertFalse(ok, "signatures from the retired key must stop verifying");

        // The new key works with no change to KasuAllowList.
        assertEq(kasuAllowList.txAuthDataSignerAddress(), address(kycSigner));
        bytes memory newKeySignature = _sign(rotatedKeyPrivate, alice, blockExpiration);
        assertTrue(_verify(alice, blockExpiration, newKeySignature));
    }

    function test_setSigningKey_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        kycSigner.setSigningKey(rotatedKey);
    }

    function test_setSigningKey_rejectsZeroAndNoop() public {
        vm.prank(admin);
        vm.expectRevert();
        kycSigner.setSigningKey(address(0));

        vm.prank(admin);
        vm.expectRevert(KasuKycSigner.SigningKeyUnchanged.selector);
        kycSigner.setSigningKey(kmsKey);
    }

    function test_constructor_rejectsZeroKey() public {
        vm.expectRevert();
        new KasuKycSigner(kasuController, address(0));
    }

    function test_isValidSignature_returnsZeroRatherThanRevertingOnGarbage() public {
        bytes32 digest = keccak256("anything");

        // Wrong length, and a well-formed signature from the wrong key.
        assertEq(kycSigner.isValidSignature(digest, hex"1234"), bytes4(0));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKeyPrivate, digest);
        assertEq(kycSigner.isValidSignature(digest, abi.encodePacked(r, s, v)), bytes4(0));

        // And the happy path still returns the ERC-1271 magic value.
        (v, r, s) = vm.sign(kmsKeyPrivate, digest);
        assertEq(kycSigner.isValidSignature(digest, abi.encodePacked(r, s, v)), bytes4(0x1626ba7e));
    }

    function test_isValidSignature_rejectsTheMalleableTwin() public {
        bytes32 digest = keccak256("anything");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(kmsKeyPrivate, digest);
        assertEq(kycSigner.isValidSignature(digest, abi.encodePacked(r, s, v)), bytes4(0x1626ba7e));

        // s' = n - s, v flipped: recovers the same address under raw ecrecover,
        // but ECDSA.tryRecover rejects high-s. KMS emits high-s roughly half the
        // time, so the backend MUST normalise before submitting.
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 flippedS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        assertEq(kycSigner.isValidSignature(digest, abi.encodePacked(r, flippedS, flippedV)), bytes4(0));
    }
}
