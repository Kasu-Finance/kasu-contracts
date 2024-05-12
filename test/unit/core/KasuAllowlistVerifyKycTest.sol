// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../_utils/BaseTestUtils.sol";
import "../../../src/core/KasuAllowList.sol";

contract KasuAllowlistVerifyKycTest is BaseTestUtils {
    address internal _lendingPoolManager = address(0x11);
    uint256 signerPrivateKey = 0xA11CE;
    address signer = vm.addr(signerPrivateKey);

    KasuAllowList kasuAllowList;

    function setUp() public {
        // we don't use controller in the tests
        IKasuController kasuController = IKasuController(address(0xcccc));

        vm.mockCall(address(kasuController), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));

        vm.mockCall(
            address(kasuController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, ROLE_KASU_ADMIN, admin),
            abi.encode(true)
        );

        KasuAllowList kasuAllowListImpl = new KasuAllowList(kasuController);
        TransparentUpgradeableProxy kasuAllowListProxy =
            new TransparentUpgradeableProxy(address(kasuAllowListImpl), admin, "");

        kasuAllowList = KasuAllowList(address(kasuAllowListProxy));

        kasuAllowList.initialize(_lendingPoolManager, signer);
    }

    function test_verifyUserKyc() public {
        // ARRANGE
        uint256 blockExpiration = block.number + 1;

        bytes memory argsWithSelector = abi.encodeCall(kasuAllowList.verifyUserKyc, (alice));

        BaseTxAuthDataVerifier.TxAuthData memory txAuthData = BaseTxAuthDataVerifier.TxAuthData({
            functionCallData: argsWithSelector,
            contractAddress: address(kasuAllowList),
            userAddress: alice,
            chainID: block.chainid,
            nonce: kasuAllowList.nonces(alice),
            blockExpiration: blockExpiration
        });

        bytes32 messageHash = kasuAllowList.getMessageHash(txAuthData);
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // ACT
        vm.prank(_lendingPoolManager);

        bytes memory callData = bytes.concat(argsWithSelector, abi.encodePacked(blockExpiration, signature));
        bytes memory response = Address.functionCall(address(kasuAllowList), callData);
        (bool isKycd) = abi.decode(response, (bool));

        // ASSERT
        assertTrue(isKycd);
    }

    function test_verifyUserKyc_onlyLendingPoolManager() public {
        // ACT & ASSERT
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILendingPoolErrors.OnlyLendingPoolManager.selector));
        kasuAllowList.verifyUserKyc(alice);
    }

    function test_setSigner() public {
        // ARRANGE
        address newSigner = address(0x1234);

        // ACT
        vm.prank(admin);
        kasuAllowList.setNexeraIDSigner(newSigner);

        // ASSERT
        assertEq(newSigner, kasuAllowList.txAuthDataSignerAddress());
    }

    function _getFakeSignature() private view returns (bytes memory) {
        bytes32 blankHash;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, blankHash);
        return abi.encodePacked(r, s, v);
    }
}
