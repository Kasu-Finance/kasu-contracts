// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
interface ILendingPoolTranche is IERC20, IERC1155 {
    struct DepositNftDetails {
        uint256 assetAmount;
        uint256 priorityLevel;
        uint256 epochId;
    }

    struct WithdrawalNftDetails {
        uint256 sharesAmount;
        uint256 priorityLevel;
        uint256 epochId;
    }

    mint 1 WithdrawalNftDetails id 2
    {
        sharesAmount: 300
        timestamp: 123
        epochId: 1
    }

    1 WithdrawalNftDetails id 2
    {
        sharesAmount: 300
        withdrawnShares: 100
        timestamp: 123
        epochId: 1
    }

    mint 300 WithdrawalNftDetails id 5
    {
        timestamp: 123
        epochId: 1
    }

    200 WithdrawalNftDetails id 5
    {
        timestamp: 123
        epochId: 1
    }

    /**
     * @dev Deposits NFTs have ids from 0 to 2^255 - 1
     */
    function mintDepositNft(address user, uint256 amount) external returns (uint256 dNftID);

    /**
     * @dev Withdrawal NFTs have ids from 2^255 to 2^256 - 1
     */
    function mintWithdrawalNft(address user, uint256 amount) external returns (uint256 wNftID);

    function getDepositNftDetails(uint256 dNftID) external view returns (DepositNftDetails memory);

    function getWithdrawalNftDetails(uint256 wNftID) external view returns (WithdrawalNftDetails memory);

    function burnDepositNft(uint256 dNftID) external;

    function burnWithdrawalNft(uint256 wNftID) external;

    /**
     * @dev mint ERC20 shares when the pending deposit is accepted
     */
    function mintShares(address user, uint256 amount) external;

    /**
     * @dev burn ERC20 shares when the pending withdrawal is accepted
     */
    function burnShares(address user, uint256 amount) external;
}
