// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "../clearing/IPendingRequestsPriorityCalculation.sol";
import {IAcceptedRequestsExecution} from "../clearing/IAcceptedRequestsExecution.sol";
import {IClearingSteps} from "../clearing/IClearingSteps.sol";

/**
 * @notice Enum where the withdrawal request came from.
 * @custom:member USER Withdrawal request came from the user.
 * @custom:member SYSTEM Withdrawal request came from the system.
 */
enum RequestedFrom {
    USER,
    SYSTEM
}

/**
 * @notice Struct containing the details of a deposit NFT.
 * @custom:member assetAmount The amount of asset requested to be deposited.
 * @custom:member tranche The tranche the deposit is requested for.
 * @custom:member epochId The epoch the deposit was requested for.
 * @custom:member priority The priority of the deposit request.
 */
struct DepositNftDetails {
    uint256 assetAmount;
    address tranche;
    uint64 epochId;
    uint8 priority;
}

/**
 * @notice Struct containing the details of a withdrawal NFT.
 * @custom:member sharesAmount The amount of tranche shares requested to be withdrawn.
 * @custom:member tranche The tranche the withdrawal is requested for.
 * @custom:member epochId The epoch the withdrawal was requested for.
 * @custom:member priority The priority of the withdrawal request.
 * @custom:member requestedFrom The source of the withdrawal request.
 */
struct WithdrawalNftDetails {
    uint256 sharesAmount;
    address tranche;
    uint64 epochId;
    uint8 priority;
    RequestedFrom requestedFrom;
}

/**
 * @notice Struct containing the input for the batch force withdrawal function.
 * @custom:member tranche The tranche the withdrawal is requested for.
 * @custom:member user The user the withdrawal is requested for.
 * @custom:member sharesToWithdraw The amount of tranche shares requested to be withdrawn.
 */
struct ForceWithdrawalInput {
    address tranche;
    address user;
    uint256 sharesToWithdraw;
}

interface IPendingPool is IERC721Enumerable, IClearingSteps {
    /* ========== EXTERNAL VIEW FUNCTIONS ========== */

    function totalPendingDepositAmount() external view returns (uint256);

    function trancheDepositNftDetails(uint256 dNftId)
        external
        view
        returns (DepositNftDetails memory depositNftDetails);

    function trancheWithdrawalNftDetails(uint256 wNftId)
        external
        view
        returns (WithdrawalNftDetails memory withdrawalNftDetails);

    function userPendingDepositAmount(address user, uint256 depositEpochId)
        external
        view
        returns (uint256 pendingDepositAmount);

    function getPendingDepositAmountForCurrentEpoch() external view returns (uint256);

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function requestDeposit(address user, address tranche, uint256 amount) external returns (uint256 dNftID);
    function cancelDepositRequest(address user, uint256 dNftID) external;
    function requestWithdrawal(address user, address tranche, uint256 trancheShares)
        external
        returns (uint256 wNftID);
    function cancelWithdrawalRequest(address user, uint256 wNftID) external;

    function forceCancelWithdrawalRequest(uint256 wNftID) external;
    function batchForceWithdrawals(ForceWithdrawalInput[] calldata input) external returns (uint256[] memory wNftIDs);
    function stop() external;

    /* ========== EVENTS ========== */

    event DepositRequested(
        address indexed user, address indexed tranche, uint256 indexed dNftID, uint256 epochId, uint256 amount
    );
    event DepositRequestCancelled(address indexed user, address indexed tranche, uint256 indexed dNftID);
    event DepositRequestAccepted(
        address indexed user,
        address indexed tranche,
        uint256 indexed dNftID,
        uint256 acceptedAmount,
        uint256 trancheSharesMinted
    );
    event DepositRequestRejected(address indexed user, address indexed tranche, uint256 indexed dNftID);
    event WithdrawalRequested(
        address indexed user, address indexed tranche, uint256 indexed wNftID, uint256 epochId, uint256 amount
    );
    event WithdrawalRequestCancelled(address indexed user, address indexed tranche, uint256 indexed wNftID);
    event WithdrawalRequestAccepted(
        address indexed user,
        address indexed tranche,
        uint256 indexed wNftID,
        uint256 acceptedShares,
        uint256 assetsWithdrawn
    );
    event ForceWithdrawalRequested(
        address indexed user, address indexed tranche, uint256 indexed wNftID, uint256 epochId, uint256 amount
    );

    /* ========== ERRORS ========== */

    error UserIsNotOwnerOfNFT(address user, uint256 dNftID);
    error NotDepositNFT(uint256 nftID);
    error NotWithdrawalNFT(uint256 nftID);
    error TooManyAssetsRequested(uint256 dNftID, uint256 availableAmount, uint256 requestedAmount);
    error TooManySharesRequested(uint256 wNftID, uint256 availableShares, uint256 requestedShares);
    error InsufficientSharesBalance(
        address user, address lendingPool, address tranche, uint256 availableShares, uint256 requestedShares
    );
    error CannotCancelSystemWithdrawalRequest(address user, uint256 wNftID);
    error CannotCancelRequestIfClearingIsPending();
    error UserCanOnlyDepositInJuniorTrancheIfHeHasLockedRKsu(address user);
    error RequestDepositAmountLessThanMinimumAllowed(
        address lendingPool,
        address tranche,
        uint256 minDepositAmountAllowed,
        uint256 totalDeposited,
        uint256 requestedAmount
    );
    error RequestDepositAmountMoreThanMaximumAllowed(
        address lendingPool,
        address tranche,
        uint256 maxDepositAmountAllowed,
        uint256 totalDeposited,
        uint256 requestedAmount
    );
    error RequestWithdrawSharesAreZero();
}
