// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

/**
 * @notice Interface for the LendingPool contract.
 * @dev Can only be called by the LendingPoolManager contract.
 */
interface ILendingPool {
    // #### USER DEPOSITS #### //
    /*
     * @notice Creates a pending deposit for the user. Transfers asset from user to lending pool
     * @dev Must approve asset token before calling this function
     * @param user The user making the pending deposit
     * @param tranche The user's desired tranche for the pending deposit
     * @param amount The amount that will be transferred to the pending deposit
     * @return The deposit NFT id that acts as a receipt for the pending deposit
     */
    function requestDeposit(address user, address tranche, uint256 amount) external returns (uint256 dNftID);

    function cancelDepositRequest(address user, address tranche, uint256 dNftID) external;

    // #### USER WITHDRAWS #### //
    /*
     * @notice Creates a pending withdrawal for the user.
     * @param user The user making the pending withdraw
     * @param tranche The pending withdrawal tranche
     * @param amount the amount that will added in the pending withdrawal
     * @return the withdrawal NFT id that acts as a receipt for the pending withdrawal
     */
    function requestWithdrawal(address user, address tranche, uint256 amount) external returns (uint256 wNftID);

    function cancelWithdrawalRequest(address user, address tranche, uint256 wNftID) external;

    // #### CLEARING #### //
    function acceptDepositRequest(address tranche, uint256 dNftID) external;

    function declineDepositRequest(address tranche, uint256 dNftID) external;

    function acceptWithdrawalRequest(address tranche, uint256 wNftID) external;

    // #### POOL DELEGATE #### //
    function borrowLoan(uint256 amount) external;

    function repayLoan(uint256 amount) external;

    function updateLoanAmount(uint256 amount) external;

    function reportLoss(uint256 amount) external returns (uint256 lossId);

    function repayLoss(uint256 lossId, uint256 amount) external;

    // #### PROTOCOL FEES #### //
    function withdrawProtocolFees() external;
}
