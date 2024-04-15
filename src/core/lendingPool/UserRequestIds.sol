// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @title UserRequestIds library
 * @notice Library for composing and decomposing NFT request IDs.
 * @dev ID consists of 160 bits for the tranche address and 96 bits for the request ID.
 * Withdrawal NFTs have a higher ID than deposit NFTs for the tranche.
 */
library UserRequestIds {
    uint256 private constant TRANCHE_START_WITHDRAWAL_NFT_ID = 2 ** 95;

    function composeDepositId(address tranche, uint256 id) internal pure returns (uint256) {
        return uint256(uint160(tranche)) | (id << 160);
    }

    function decomposeDepositId(uint256 id) internal pure returns (address tranche, uint256 depositId) {
        tranche = address(uint160(id << 96 >> 96));
        depositId = id >> 160;
    }

    function composeWithdrawalId(address tranche, uint256 id) internal pure returns (uint256) {
        return uint256(uint160(tranche)) | ((id + TRANCHE_START_WITHDRAWAL_NFT_ID) << 160);
    }

    function decomposeWithdrawalId(uint256 id) internal pure returns (address tranche, uint256 withdrawalId) {
        tranche = address(uint160(id << 96 >> 96));
        withdrawalId = (id >> 160) - TRANCHE_START_WITHDRAWAL_NFT_ID;
    }

    function isDepositNft(uint256 nftId) internal pure returns (bool) {
        return (nftId >> 160) < TRANCHE_START_WITHDRAWAL_NFT_ID;
    }
}
