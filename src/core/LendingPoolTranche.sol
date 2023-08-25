// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";

/**
 * @dev 
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPoolTranche is ERC20Upgradeable, ERC1155Upgradeable {
    /// @note user => nftIDs[]
    mapping(address => uint256[]) private userDepositNFTs;
    
    /// @note user => nftIDs[]
    mapping(address => uint256[]) private userWithdrawalNFTs;
}
