// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

struct LossDetails {
    uint256 lossAmount;
    uint256 usersCount;
    uint256 usersMintedCount;
    uint256 recoveredAmount;
    uint256 totalLossShares;
}

interface ILendingPoolTrancheLoss {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function minimumAssetAmountLeftAfterLoss() external view returns (uint256);

    function userClaimedLosses(address user, uint256 lossId) external view returns (uint256 claimedAmount);

    function lossDetails(uint256 lossId) external view returns (LossDetails memory);

    function isLossMintingComplete(uint256 lossId) external view returns (bool);

    function isPendingLossMint() external view returns (bool);

    function userClaimableLoss(address user, uint256 lossId) external view returns (uint256 claimableAmount);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function registerTrancheLoss(uint256 lossId, uint256 lossAmount, bool doMintLossTokens)
        external
        returns (uint256 lossApplied);

    function batchMintLossTokens(uint256 lossId, uint256 batchSize) external;

    function repayLoss(uint256 lossId, uint256 amount) external;

    function claimRepaidLoss(address user, uint256 lossId) external returns (uint256 claimedAmount);

    /* ========== EVENTS ========== */

    event LossRegistered(uint256 indexed lossId, uint256 lossAmount, uint256 usersCount);
    event LossReturned(uint256 indexed lossId, uint256 amount);
    event LossClaimed(address indexed user, uint256 indexed lossId, uint256 amount);
    event MintedLossTokensToUsers(uint256 indexed lossId, uint256 batchCount);
    event LossMintingComplete(uint256 indexed lossId);

    /* ========== ERRORS ========== */

    error LossMintingNotYetComplete(uint256 lossId);
    error LossMintAlreadyComplete(uint256 lossId);
    error LossIdNotValid(uint256 lossId);
    error LossMintingInProgress(uint256 lossId);
}
