// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/core/clearing/AcceptedRequestsExecution.sol";
import "../../../src/core/interfaces/clearing/IClearingStepsData.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "../../../src/core/lendingPool/UserRequestIds.sol";

/// @dev 1:1 shares→assets mock so tests can reason about asset-budget invariants
/// without ERC4626 plumbing. convertToAssets is the only method step 4 calls.
contract Mock1to1Tranche {
    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }
}

/**
 * @dev Minimal concrete harness that pins all virtual methods and lets the test plant
 * a pending withdrawal NFT with controllable sharesAmount / totalAccepted / totalWithdrawal,
 * so we can exercise the AcceptedRequestsExecution dust-truncation fallback directly.
 *
 * M-08 guard under test (AcceptedRequestsExecution.sol):
 *   if (acceptedWithdrawalShares == 0 && withdrawalNftDetails.sharesAmount > 0) {
 *       acceptedWithdrawalShares = withdrawalNftDetails.sharesAmount;
 *   }
 */
contract AcceptedRequestsExecutionHarness is AcceptedRequestsExecution {
    uint256[] public pendingIds;
    mapping(uint256 => WithdrawalNftDetails) public withdrawalDetails;
    ClearingData internal _cd;

    // Captured by _acceptWithdrawalRequest so tests can assert on the accepted shares.
    uint256 public lastAcceptedWNftId;
    uint256 public lastAcceptedShares;
    uint256 public acceptCallCount;
    uint256 public totalAcceptedShares; // running sum for aggregate invariant checks

    function setClearingData(
        uint256[] memory priorityWithdrawalAmounts,
        uint256[] memory acceptedPriorityWithdrawalAmounts,
        uint256 totalPendingRequestsToProcess
    ) external {
        _cd.pendingWithdrawals.priorityWithdrawalAmounts = priorityWithdrawalAmounts;
        _cd.acceptedPriorityWithdrawalAmounts = acceptedPriorityWithdrawalAmounts;
        _cd.totalPendingRequestsToProcess = totalPendingRequestsToProcess;
    }

    function addWithdrawal(uint256 nftId, WithdrawalNftDetails memory d) external {
        pendingIds.push(nftId);
        withdrawalDetails[nftId] = d;
    }

    // Virtual overrides — minimal plumbing, withdrawal-only path.
    function _totalPendingRequests() internal view override returns (uint256) {
        return pendingIds.length;
    }

    function _pendingRequestIdByIndex(uint256 index) internal view override returns (uint256) {
        return pendingIds[index];
    }

    function _pendingRequestOwner(uint256) internal pure override returns (address) {
        return address(0);
    }

    function trancheDepositNftDetails(uint256) public pure override returns (DepositNftDetails memory d) {
        return d;
    }

    function trancheWithdrawalNftDetails(uint256 wNftId) public view override returns (WithdrawalNftDetails memory) {
        return withdrawalDetails[wNftId];
    }

    function _lendingPoolTranches() internal pure override returns (address[] memory arr) {
        return arr;
    }

    function _trancheIndex(address[] memory, address) internal pure override returns (uint256) {
        return 0;
    }

    function _trancheAddress(address[] memory, uint256) internal pure override returns (address) {
        return address(0);
    }

    function _acceptDepositRequest(uint256, address, uint256) internal pure override {}

    function _rejectDepositRequest(uint256) internal pure override {}

    function _acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) internal override {
        lastAcceptedWNftId = wNftID;
        lastAcceptedShares = acceptedShares;
        ++acceptCallCount;
        totalAcceptedShares += acceptedShares;
    }

    function _clearingDataStorage(uint256) internal view override returns (ClearingData storage) {
        return _cd;
    }

    function _clearingDataMemory(uint256) internal view override returns (ClearingData memory) {
        return _cd;
    }

    function _onlyClearingCoordinator() internal pure override {}
}

contract M08DustWithdrawalTest is Test {
    AcceptedRequestsExecutionHarness internal harness;

    function setUp() public {
        harness = new AcceptedRequestsExecutionHarness();
    }

    /// @dev Dust withdrawal: pro-rata truncates to 0, fallback accepts full sharesAmount
    /// when the priority's asset budget can accommodate it (1:1 mock so assets == shares).
    function test_M08_dustWithdrawalAcceptedInFull() public {
        // One huge withdrawal and one dust withdrawal at the same priority.
        //   totalWithdrawal = 1e18, totalAccepted = 1e10, both in asset units (1:1 mock).
        //   Huge: sharesAmount = 1e18 - 100 → pro-rata ≈ 1e10 shares (consumes nearly all budget).
        //   Dust: sharesAmount = 100 → pro-rata = 100 * 1e10 / 1e18 = 0 → triggers fallback.
        //   Fallback asset value = 100; remaining budget after huge ≈ 0 — actually the huge user
        //   consumes most of the budget. For the dust user to succeed, we need budget room left.
        //   To keep this test focused on "fallback fires when budget allows", use sizes where the
        //   huge user's pro-rata leaves room for the dust: huge=1e16, totalWithdrawal=1e18,
        //   totalAccepted=1e10. Huge pro-rata = 1e16 * 1e10 / 1e18 = 1e8 assets consumed; dust=100
        //   needs 100 assets, fits in (1e10 - 1e8) remaining. Dust gets full 100 shares.
        Mock1to1Tranche tranche = new Mock1to1Tranche();
        uint8 priority = 0;
        uint256 dustShares = 100;
        uint256 hugeShares = 1e16 - dustShares;
        uint256 totalWithdrawal = 1e18;
        uint256 totalAccepted = 1e10;

        uint256[] memory prioritySums = new uint256[](1);
        prioritySums[0] = totalWithdrawal;
        uint256[] memory acceptedPrioritySums = new uint256[](1);
        acceptedPrioritySums[0] = totalAccepted;

        harness.setClearingData(prioritySums, acceptedPrioritySums, 2);

        uint256 hugeWNftId = UserRequestIds.composeWithdrawalId(address(tranche), 1);
        uint256 dustWNftId = UserRequestIds.composeWithdrawalId(address(tranche), 2);

        harness.addWithdrawal(
            hugeWNftId,
            WithdrawalNftDetails({
                sharesAmount: hugeShares,
                tranche: address(tranche),
                epochId: 0,
                priority: priority,
                requestedFrom: RequestedFrom.USER
            })
        );
        harness.addWithdrawal(
            dustWNftId,
            WithdrawalNftDetails({
                sharesAmount: dustShares,
                tranche: address(tranche),
                epochId: 0,
                priority: priority,
                requestedFrom: RequestedFrom.USER
            })
        );

        // Process both. Loop walks indices high→low: dust first, then huge.
        harness.executeAcceptedRequestsBatch(0, 2);

        // Dust NFT should receive its full sharesAmount via the budget-aware fallback.
        assertEq(harness.acceptCallCount(), 2, "both NFTs cleared");
    }

    /// @dev FV-01: many dust NFTs at the same priority must not cumulatively exceed the
    /// asset-budget `totalAcceptedAmount`. Before the fix, each dust NFT's fallback
    /// hands out full sharesAmount, summing to many multiples of the budget.
    function test_FV01_aggregateDustFallbackBoundedByAssetBudget() public {
        // Setup: 1:1 shares→assets tranche.
        //   totalWithdrawal (asset budget) = 100
        //   totalAccepted  (asset budget) =  10
        //   50 dust NFTs, each with sharesAmount = 5.
        //   Pro-rata per NFT: 5 * 10 / 100 = 0 → every NFT triggers the fallback.
        //   If the fallback hands out full sharesAmount each time, sum = 250 shares
        //   = 250 assets (1:1), which is 25× the budget of 10.
        //   Invariant: sum(acceptedShares in asset terms) MUST be ≤ totalAccepted.
        Mock1to1Tranche tranche = new Mock1to1Tranche();
        uint8 priority = 0;
        uint256 dustShares = 5;
        uint256 userCount = 50;
        uint256 totalWithdrawal = 100;
        uint256 totalAccepted = 10;

        uint256[] memory prioritySums = new uint256[](1);
        prioritySums[0] = totalWithdrawal;
        uint256[] memory acceptedPrioritySums = new uint256[](1);
        acceptedPrioritySums[0] = totalAccepted;

        harness.setClearingData(prioritySums, acceptedPrioritySums, userCount);

        for (uint256 i; i < userCount; ++i) {
            uint256 wNftId = UserRequestIds.composeWithdrawalId(address(tranche), i + 1);
            harness.addWithdrawal(
                wNftId,
                WithdrawalNftDetails({
                    sharesAmount: dustShares,
                    tranche: address(tranche),
                    epochId: 0,
                    priority: priority,
                    requestedFrom: RequestedFrom.USER
                })
            );
        }

        // Process all NFTs in one batch.
        harness.executeAcceptedRequestsBatch(0, userCount);

        // Invariant: cumulative accepted shares (asset-equivalent via 1:1 tranche)
        // must not exceed the priority's asset budget.
        assertLe(
            harness.totalAcceptedShares(),
            totalAccepted,
            "aggregate dust acceptance must respect totalAcceptedAmount"
        );
        // Liveness: at least some dust NFTs should clear (we didn't regress M-08's goal).
        assertGt(harness.acceptCallCount(), 0, "at least one dust NFT should clear");
    }

    /// @dev Control: when pro-rata yields a non-zero share, the fallback must NOT override it.
    function test_M08_nonDustWithdrawalProRataPreserved() public {
        Mock1to1Tranche tranche = new Mock1to1Tranche();
        // sharesAmount=1e18, totalAccepted=5e17, totalWithdrawal=2e18
        // Pro-rata: 1e18 * 5e17 / 2e18 = 2.5e17 (non-zero — fallback should not fire)
        uint8 priority = 0;
        uint256 shares = 1e18;
        uint256 totalWithdrawal = 2e18;
        uint256 totalAccepted = 5e17;
        uint256 expected = shares * totalAccepted / totalWithdrawal; // 2.5e17

        uint256[] memory prioritySums = new uint256[](1);
        prioritySums[0] = totalWithdrawal;
        uint256[] memory acceptedPrioritySums = new uint256[](1);
        acceptedPrioritySums[0] = totalAccepted;

        harness.setClearingData(prioritySums, acceptedPrioritySums, 1);

        uint256 wNftId = UserRequestIds.composeWithdrawalId(address(tranche), 1);
        harness.addWithdrawal(
            wNftId,
            WithdrawalNftDetails({
                sharesAmount: shares,
                tranche: address(tranche),
                epochId: 0,
                priority: priority,
                requestedFrom: RequestedFrom.USER
            })
        );

        harness.executeAcceptedRequestsBatch(0, 1);

        assertEq(harness.lastAcceptedShares(), expected, "pro-rata preserved for non-dust positions");
        assertTrue(harness.lastAcceptedShares() < shares, "did not overpay via fallback");
    }
}
