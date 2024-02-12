// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

struct DepositNftDetails {
    uint256 assetAmount;
    address tranche;
    uint256 priorityLevel;
    uint256 epochId;
}

struct WithdrawalNftDetails {
    uint256 sharesAmount;
    uint256 priorityLevel;
    uint256 epochId;
}

struct ForceWithdrawalInput {
    address tranche;
    address user;
    uint256 sharesToWithdraw;
}

/**
 * @notice Interface for the LendingPool contract.
 * @dev Can only be called by the LendingPoolManager contract.
 */
interface IPendingPool is IERC721 {
    // VIEWS
    function trancheDepositNftDetails(uint256 dNftId) external returns (DepositNftDetails memory depositNftDetails);
    function trancheWithdrawalNftDetails(uint256 wNftId)
        external
        returns (WithdrawalNftDetails memory withdrawalNftDetails);

    // #### USER DEPOSITS #### //
    /**
     * @notice Creates a pending deposit for the user. Transfers asset from user to lending pool
     * @dev Must approve asset token before calling this function
     * @param user The user making the pending deposit
     * @param tranche The user's desired tranche for the pending deposit
     * @param amount The amount that will be transferred to the pending deposit
     * @return dNftID The deposit NFT id that acts as a receipt for the pending deposit
     */
    function requestDeposit(address user, address tranche, uint256 amount) external returns (uint256 dNftID);

    function cancelDepositRequest(address user, uint256 dNftID) external;

    // #### USER WITHDRAWS #### //
    /**
     * @notice Creates a pending withdrawal for the user.
     * @param user The user making the pending withdraw
     * @param tranche The pending withdrawal tranche
     * @param trancheShares the amount of shares that will added in the pending withdrawal
     * @return wNftID the withdrawal NFT id that acts as a receipt for the pending withdrawal
     */
    function requestWithdrawal(address user, address tranche, uint256 trancheShares)
        external
        returns (uint256 wNftID);

    function cancelWithdrawalRequest(address user, uint256 wNftID) external;

    function batchForceWithdrawals(ForceWithdrawalInput[] calldata input) external returns (uint256[] memory wNftIDs);

    function stop() external;

    // Events
    event DepositRequested(
        address indexed user, address indexed tranche, uint256 indexed dNftID, uint256 epoch, uint256 amount
    );
    event DepositRequestCancelled(address indexed user, address indexed tranche, uint256 indexed dNftID);
    event WithdrawalRequested(address indexed user, address indexed tranche, uint256 indexed wNftID, uint256 amount);
    event WithdrawalRequestCancelled(address indexed user, address indexed tranche, uint256 indexed wNftID);
    event ForceWithdrawalRequested(
        address indexed user, address indexed tranche, uint256 indexed wNftID, uint256 amount
    );

    // Errors
    error UserIsNotOwnerOfNFT(address user, uint256 dNftID);
    error TooManyAssetsRequested(uint256 dNftID, uint256 availableAmount, uint256 requestedAmount);
    error TooManySharesRequested(uint256 wNftID, uint256 availableShares, uint256 requestedShares);
    error InsufficientSharesBalance(
        address user, address lendingPool, address tranche, uint256 availableShares, uint256 requestedShares
    );
    error WithdrawalRequestIsForced(address user, address lendingPool, uint256 wNftID);
}
