// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../_utils/BaseTestUtils.sol";
import "../../../src/core/KasuAllowList.sol";

contract KasuAllowlistVerifyKycTest is BaseTestUtils {
    address internal _lendingPoolManager = address(0x11);
    uint256 signerPrivateKey = 0xA11CE;
    address signer = vm.addr(signerPrivateKey);

    ByteSlicer bs;
    KasuAllowList kasuAllowList;

    function setUp() public {
        // we don't use controller in the tests
        IKasuController kasuController = IKasuController(address(0xcccc));
        KasuAllowList kasuAllowListImpl = new KasuAllowList(kasuController);

        TransparentUpgradeableProxy kasuControllerProxy =
            new TransparentUpgradeableProxy(address(kasuAllowListImpl), admin, "");

        kasuAllowList = KasuAllowList(address(kasuControllerProxy));

        kasuAllowList.initialize(_lendingPoolManager, signer);

        bs = new ByteSlicer();
    }

    function test_verifyUserKyc() public {
        // ARRANGE
        uint256 blockExpiration = block.number + 1;

        bytes memory callDataFake =
            abi.encodeCall(kasuAllowList.verifyUserKyc, (alice, blockExpiration, _getFakeSignature()));

        bytes memory argsWithSelector = bs.sliceEnd(callDataFake, 128);

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
        bool isKycd = kasuAllowList.verifyUserKyc(alice, blockExpiration, signature);

        // ASSERT
        assertTrue(isKycd);
    }

    function _getFakeSignature() private view returns (bytes memory) {
        bytes32 blankHash;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, blankHash);
        return abi.encodePacked(r, s, v);
    }
}

contract ByteSlicer {
    function sliceEnd(bytes calldata data, uint256 sliceFor) external pure returns (bytes memory) {
        return data[:data.length - sliceFor];
    }

    function test_byteSlicer() external pure {}
}
