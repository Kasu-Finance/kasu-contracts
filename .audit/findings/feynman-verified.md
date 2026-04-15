# Feynman Audit — Verified Findings (release-candidate)

## Scope
- Language: Solidity 0.8.23
- Branch: `release-candidate`
- Modules analyzed: full `src/core/**` surface + `src/locking/KSULocking.sol`, `src/locking/rKSU.sol`
- Priority targets: the four post-April-2026 fix sites (M-03, M-04, M-06, M-08), clearing pipeline (all 4 steps), loss flow, waterfall, pending pool / NFT flow, user manager / loyalty, system variables, locking, fee manager, fixed-term deposits, swap.
- Audit mode: trust-but-verify — the four fixes were re-derived independently and the full attack-surface re-walked under Feynman Q1–Q7.

## Verification Summary

| ID | Feynman Q | Title | Original | Verdict | Final |
|----|-----------|-------|----------|---------|-------|
| FV-01 | Q1.4, Q5.2, Q7.7 | Dust-truncation fallback bypasses clearing-liquidity budget | MEDIUM | TRUE POSITIVE | MEDIUM |
| FV-02 | Q5.1, Q6.4 | `registerTrancheLoss` with `usersCount == 0` permanently traps repaid funds | LOW | TRUE POSITIVE | LOW |
| FV-03 | Q1.3, Q6.1 | `_postSwap` sweeps the entire underlyingAsset balance of LendingPoolManager to msg.sender | LOW | TRUE POSITIVE (informational) | LOW |
| FV-04 | Q4.2 | `emitUserLoyaltyRewardBatch` trusts admin-supplied `ksuTokenPrice` parameter without bounds | LOW | TRUE POSITIVE (acknowledged) | LOW |

**Result: 0 Critical, 0 High, 1 Medium, 3 Low.** All four April-2026 fixes (M-03, M-04, M-06, M-08) were re-derived and confirmed sound in the specific scenarios they target. The single Medium below is an edge of the M-08 fix that the prior audit did not fully characterise.

---

## Verified findings

### FV-01 — Dust-truncation fallback can inflate accepted withdrawals beyond the clearing-liquidity budget (MEDIUM / Liveness)

**File:** `src/core/clearing/AcceptedRequestsExecution.sol`
**Lines:** 203–212
**Feynman question that exposed this:**
> Q1.4 "Is this check SUFFICIENT for what it's trying to prevent?"
> Q5.2 "What if the last element removal breaks an invariant?"
> Q7.7 "Does the accumulated state from MULTIPLE calls create a condition that a SINGLE call can never reach?"

**Code:**
```solidity
uint256 acceptedWithdrawalShares =
    withdrawalNftDetails.sharesAmount * totalAcceptedAmount / totalWithdrawalAmount;

// prevent dust positions from being permanently stuck due to truncation to 0
if (acceptedWithdrawalShares == 0 && withdrawalNftDetails.sharesAmount > 0) {
    acceptedWithdrawalShares = withdrawalNftDetails.sharesAmount;
}

_acceptWithdrawalRequest(userRequestNftId, acceptedWithdrawalShares);
```

**Why this is wrong (first-principles):**

The clearing calculator picks `totalAcceptedAmount` (asset value) so that the pool can actually honour every dollar accepted:
`excess + acceptedDeposits ≥ acceptedWithdrawal + drawAmount` (`AcceptedRequestsCalculation._verifyResult`, lines 452–457).
Per-user acceptance preserves this invariant only when each user gets their *proportional* share of the budget: `userShares * totalAccepted / totalWithdrawal`.

The M-08 dust fix replaces the proportional result with the user's **full** `sharesAmount` whenever the proportional result truncates to zero. The fallback fires for every user whose `sharesAmount * totalAccepted < totalWithdrawal` — that is, every user whose asset value is below `1 / acceptanceRatio`. When the acceptance ratio is small (the pool is liquidity-constrained, which is exactly when the fallback triggers in practice) the set of dust users can cover most or all of the withdrawers.

In the extreme: `totalAccepted = 1 asset unit`, `totalWithdrawal = $500`, 1 000 depositors each with $0.50 of shares. Every depositor would receive 0 shares under the strict formula — the fallback hands each the full balance, so the **actually accepted** asset total jumps from $1 to $500. The pool only reserved $1 of USDC for this priority after accounting for draws / minExcess, so the very next `LendingPool.acceptWithdrawal` → `_transferAssets(user, assetAmount)` call reverts with insufficient USDC balance.

Because `executeAcceptedRequestsBatch` writes its progress pointer (`_acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = i`) only on the happy path *after* the loop exits (line 228), every retry rediscovers the same over-acceptance and reverts again. Step 4 cannot advance without external intervention (admin funding the pool, or manager adjusting the draw amount via a later-epoch action).

**Verification evidence (code trace):**

1. `AcceptedRequestsCalculation._verifyResult` (line 452–457) guarantees the budget invariant *in asset terms*: `excess + acceptedDep ≥ acceptedWd + draw`. ✅
2. `_calculateAcceptedWithdrawalAmountsForEachPriority` (line 360–374) splits `acceptedWithdrawalAmount` across priorities — each priority's budget is fixed. ✅
3. Step 4 execution at the per-user level (lines 203–212) converts priority-budget back to shares via `userShares * totalAccepted / totalWd`. When the fallback short-circuits this, the sum of `acceptedWithdrawalShares` across all users in a priority can exceed `totalAcceptedAmount` in asset-value terms. Bound: `Σ over dust users ≤ priorityTotalShares`, which in the worst case equals the *entire* pending priority withdrawal, not the allocated fraction.
4. `LendingPool.acceptWithdrawal` (lines 400–418) calls `tranche.redeem` (burns tranche shares, mints pool-tokens back to lending pool) then `_burn(address(this), assetAmount)` and `_transferAssets(user, assetAmount)`. The last line reverts if lending pool's USDC balance is below `assetAmount` — which is exactly the condition when the fallback's over-acceptance races past the pool's free liquidity.
5. `_acceptedRequestsExecutionPerEpoch[targetEpoch].nextIndexToProcess = i;` is outside the loop (line 228). A mid-loop revert discards the batch's progress, so the same wNFT will be revisited in the next call and re-revert.

**Attack / triggering sequence:**

1. A pool reaches an epoch where desired draws consume most of the excess; `_calculateDepositAndWithdrawalAmounts` computes a small `acceptedWithdrawalAmount` (tens or hundreds of dollars).
2. Many small depositors (natural long tail in a lending pool) request withdrawals. Their per-user `sharesAmount * totalAccepted / totalWithdrawal` truncates to 0.
3. Step 3 passes `_verifyResult` because it is computed against asset totals, not reconstructed from per-user shares.
4. Step 4 batch starts processing. For every dust user, the fallback hands them their full share amount. Cumulative burns / transfers blow past the pool's free USDC.
5. The first user whose transfer cannot be satisfied reverts the whole batch. Next call: same revert. Clearing is wedged on step 4 until either (a) funds are added to the pool, (b) the pool manager externally drains the wNFT queue via an out-of-band path (none exists in the Lite contracts), or (c) epoch is skipped via admin intervention.

**Impact:**

- *Primary*: Permanent step-4 DoS for the current clearing epoch under a legitimate (non-adversarial) long-tail withdrawal pattern; recovery requires admin-level mitigation (funding USDC into the pool).
- *Secondary*: Even if the pool *does* have the liquidity to honour the inflated amount, fairness is broken — dust users are paid 100% while non-dust users are only paid the proportional fraction. Over many epochs this biases the pool in favour of micro-positions.

No direct fund loss occurs (the revert protects the solvency invariant), hence MEDIUM not HIGH.

**Suggested fix (minimal, asset-domain-preserving):**

Cap the dust fallback at the priority's remaining asset budget rather than handing out full shares, *or* perform the priority's per-user allocation iteratively with a running remainder so the sum is exactly equal to `totalAcceptedAmount`:

```solidity
// Option A — cap the dust hand-out:
if (acceptedWithdrawalShares == 0 && withdrawalNftDetails.sharesAmount > 0) {
    // Give the user their full shares only if doing so does not exceed the priority's
    // remaining asset budget (tracked in a new running variable initialised to
    // totalAcceptedAmount on the first touch of this priority in the batch).
    uint256 fullShareAssetValue =
        ILendingPoolTranche(wNftTranche).convertToAssets(withdrawalNftDetails.sharesAmount);
    if (fullShareAssetValue <= remainingPriorityBudget) {
        acceptedWithdrawalShares = withdrawalNftDetails.sharesAmount;
        remainingPriorityBudget -= fullShareAssetValue;
    }
    // else: leave as 0, this dust position rolls to the next epoch — same as before M-08
}
```

Option B (iterative remainder) preserves exact summing but requires restructuring step 4 to process per-priority rather than per-NFT; Option A is the minimal change.

---

### FV-02 — `registerTrancheLoss` when the tranche has zero users locks repaid assets forever (LOW)

**File:** `src/core/lendingPool/LendingPoolTrancheLoss.sol`
**Lines:** 113–128, 246–261, 151–164, 93–102
**Feynman question that exposed this:**
> Q5.1 "What happens on the FIRST call to this function? (Empty state)"
> Q6.4 "Is there a code path where NO return and NO error happens?"

**Code:**
```solidity
function _registerLoss(uint256 lossId, uint256 lossAmount, uint256 batchSize) internal {
    address[] storage users = _trancheUsersStorage();
    uint256 usersCount = users.length;

    _lossDetails[lossId] = LossDetails(lossAmount, usersCount, 0, 0, 0);
    ...
    if (usersCount > 0) {
        _pendingMintLossId = lossId;
        ...
    }
}
```
And later:
```solidity
function _isLossMintingComplete(uint256 lossId) internal view returns (bool) {
    return _lossDetails[lossId].usersCount == _lossDetails[lossId].usersMintedCount;
}
```

**Why this is wrong:**

If `registerTrancheLoss` is invoked when `_trancheUsers.length == 0`, the loss is recorded with `usersCount=0` and `totalLossShares=0`. `_isLossMintingComplete` trivially returns `true` (0 == 0). `repayLoss` (line 151) therefore succeeds and accumulates `recoveredAmount`, transferring USDC into the tranche. But `userClaimableLoss` (line 93–102) gates on `totalLossShares > 0` — with `totalLossShares=0`, every user's claimable is zero forever, and `claimRepaidLoss` always returns 0.

Result: the repaid USDC is stuck inside the tranche with no on-chain withdrawal path.

**Verification evidence:**

- `_trancheUsers` shrinks in `removeUserActiveShares` (LendingPoolTranche.sol L106-121). A tranche that was fully withdrawn to 0 holders but still has residual `totalAssets()` (e.g. stranded from rounding on previous losses, or first-loss-capital repayment) could legitimately hit this path.
- `calculateMaximumLossAmount = totalAssets - minimumAssetAmountLeftAfterLoss`. If `totalAssets > minimumAssetAmountLeftAfterLoss` with zero users, `lossAmount > 0` is accepted by `registerTrancheLoss` and the zero-user branch is taken.
- No code path exists to un-stick `recoveredAmount` once in this state.

**Impact:** Low. The scenario requires a tranche with zero active users but non-dust `totalAssets`. Extremely rare but possible after a series of losses + first-loss-capital events. Funds trapped are bounded by pool-manager-injected repayments.

**Suggested fix:**

Early-revert `registerTrancheLoss` when `_trancheUsers.length == 0` (there is no one to bear the loss), or reject `repayLoss` for a `lossId` whose `totalLossShares == 0`.

---

### FV-03 — `_postSwap` sweeps *all* underlying-asset balance of LendingPoolManager to the caller (LOW / informational)

**File:** `src/core/DepositSwap.sol`
**Lines:** 113–135 (function), called from `LendingPoolManager._requestDeposit` L790
**Feynman question that exposed this:**
> Q1.3 "What specific attack motivated this check? Trace the zero/max value through the entire function."
> Q6.1 "What does this function return? Who consumes the return value?"

**Code:**
```solidity
function _postSwap(address[] memory inTokens, address outToken) internal {
    ...
    // Return outToken if any.
    returnBalance = IERC20(outToken).balanceOf(address(this));
    if (returnBalance > 0) {
        IERC20(outToken).safeTransfer(msg.sender, returnBalance);
    }
    ...
}
```

**Why this is (barely) wrong:**

`_postSwap` forwards the **entire current balance** of the outToken — not just the swap leftovers — to `msg.sender`. Under normal operation, `_requestDeposit` transfers in via `_transferAssetsFrom(msg.sender, address(this), amount)` and immediately forwards the same `amount` to `PendingPool.requestDeposit` through `_approveAsset + pendingPool.pull`. After that, LendingPoolManager's USDC balance is expected to be zero, and the sweep returns only true swap dust.

**But** the other mutative methods on LendingPoolManager (`repayOwedFunds`, `repayLoss`, `depositFirstLossCapital`, L339–383) use the same `this → approve → pool.pull` pattern. If any one of those ever leaves residue on the manager (e.g. a pool-side function reverts silently on part of the amount, or a hand-rolled integration transfers directly into LendingPoolManager outside the expected patterns), the next unrelated user's `_requestDeposit` sweeps the residue.

**Verification evidence:**

- I traced every place `_underlyingAsset` crosses the LendingPoolManager boundary (grep of `_transferAssets` + `safeTransfer*` in LendingPoolManager.sol: lines 346, 364, 380, 781 only). All four sites pair a pull-in with an immediate push-out, and none leaves residue on success.
- On a revert inside the downstream `pool.xxx` call, the whole tx rolls back — so *direct* residue from these four flows is impossible.
- The sweep is only dangerous if *someone else* pushes USDC to the manager: e.g. an operator mistakenly transfers tokens, or a future upgrade introduces a flow that leaves residue. Today, no such flow exists.

**Impact:** Low; informational. The invariant "LendingPoolManager never holds underlyingAsset between transactions" is load-bearing for the sweep to be safe, and that invariant currently holds but is not enforced in code. Any future patch that breaks the invariant silently donates funds to the first caller of `_requestDeposit` that uses swapData.

**Suggested fix:** Track the swap-specific residue explicitly (`balanceAfterSwap - amountDeposited`) and return only that, not `balanceOf(this)`. One-line change and it costs nothing.

---

### FV-04 — `emitUserLoyaltyRewardBatch` honours an admin-supplied `ksuTokenPrice` without freshness or bounds (LOW / acknowledged)

**File:** `src/core/UserLoyaltyRewards.sol`
**Lines:** 148–184
**Feynman question that exposed this:**
> Q4.2 "What does this function assume about EXTERNAL DATA it receives?"
> Q4.5 "Can the value be manipulated? What if precision differs?"

**Code:**
```solidity
function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata userRewardInputs, uint256 ksuTokenPrice)
    external
    onlyAdmin
{
    ...
    if (ksuTokenPrice == 0) {
        ksuTokenPrice = _ksuPrice.ksuTokenPrice();
    }
    ...
    // reward size is inversely proportional to ksuTokenPrice
}
```

**Why this is borderline:**

`_emitUserLoyaltyReward` computes `ksuReward = amountDeposited * rate * KSU_PRICE_MULTIPLIER * 1e12 / ksuTokenPrice / INTEREST_RATE_FULL_PERCENT`. A tiny `ksuTokenPrice` inflates `ksuReward` without bound; the M-03 caps (`perUserCap`, `batchCap`) are then the only defence against a misbehaving (or compromised) admin.

The caps *are* enforced (M-03 is sound), so the blast radius is one batch. But the parameter is unvalidated: no sanity check, no freshness check, not bounded to `_ksuPrice.ksuTokenPrice()`.

**Verification evidence:**

- The caps at lines 152–157 and 174–182 correctly revert before the batch can mint `> batchCap` or `> perUserCap` KSU. State is rolled back on revert (happy-path writes in `_emitUserLoyaltyReward` are reverted with it).
- `ksuTokenPrice` has no validation when non-zero.
- Trust model: `onlyAdmin` is the Kasu multisig; this is an acknowledged admin-trust surface.

**Impact:** Low. With M-03 caps the worst case is that a single compromised admin tx mints up to `batchCap` KSU inflated in recipient-count distribution. No user funds are touched; KSU can be burned by the admin path if required. This is essentially an admin-trust warning.

**Suggested fix:**

Compare the supplied price against `_ksuPrice.ksuTokenPrice()` and revert on > N% deviation, or just remove the parameter and always read from `_ksuPrice`. The parameter exists to allow a single-tx batch price-snapshot, but deviating significantly from the oracle is not a supported use case.

---

## Re-verification of the four prior fixes (M-03, M-04, M-06, M-08)

### M-03 — reward caps in `emitUserLoyaltyRewardBatch`
Re-derived: caps are checked after `_emitUserLoyaltyReward` increments `userRewards[user]` and `totalUnclaimedRewards`, but a revert rolls back those writes, so the post-check ordering is safe. `setRewardCaps(0, 0)` disables the path. No issue beyond FV-04 (the unvalidated price parameter).

### M-04 — `ksuEpochTokenPriceFresh` + mutative self-heal
Re-derived: `batchCalculateUserLoyaltyLevels` calls `updateKsuEpochTokenPrice` at the top (idempotent — no-op if `priceUpdateEpoch == currentEpochNumber()`). `_loyaltyParameters` reads `ksuEpochTokenPriceFresh` which falls back to spot price for view-only callers. Both halves correct. The snapshot is frozen across the batches of one clearing epoch (subsequent batches' `updateKsuEpochTokenPrice` is a no-op), which is the intended behaviour. Sound.

### M-06 — CLEARING_MINT_BATCH_SIZE self-heal in step 4
Re-derived: the loop at `AcceptedRequestsExecution.sol:92–101` iterates every tranche, drains up to 100 pending loss-mint entries per tranche, and reverts with `LossMintingStillPending` if any tranche still has pending mints after the drain. `notPendingLossMint` modifier on `deposit`/`redeem` in `LendingPoolTranche.sol:139,170` guarantees the self-heal must complete before any subsequent `_acceptDepositRequest` / `_acceptWithdrawalRequest` touches the tranche. The pending-mint state is shared across tranches by `lossId` but tracked per-tranche via each tranche's own `_pendingMintLossId`, so the loop correctly handles mixed states. Sound.

### M-08 — dust-truncation fallback
Re-derived: the original bug (dust users' withdrawals rolling forever because `shares*acc/total == 0`) is real and the fallback does fix that user-facing symptom. **However**, the fallback as written is unbounded, introducing FV-01 above. The intent is correct; the implementation needs a priority-budget cap.

---

## False positives eliminated (hypotheses checked and discarded)

1. **"Deposit NFT id 0 collides with the `_dNftIdPerUser...==0` sentinel"** — `_setUpTranches` initialises `_nextTrancheDepositNFTId[tranche] = composeDepositId(tranche, 0) = uint256(uint160(tranche))`, which is non-zero for any real tranche address. First-deposit dNFTID is never 0. Sound.
2. **"`_postSwap` ETH refund leaks protocol ETH"** — LendingPoolManager holds no persistent ETH; refund path only runs when `msg.value > 0`. Not exploitable today.
3. **"`updateUserLendingPools` during clearing corrupts loyalty snapshot"** — guarded by `if (_systemVariables.isClearingTime()) revert CannotExecuteDuringClearingTime()` at UserManager.sol:366–368. Sound.
4. **"`userRequestedDeposit` can grow `_allUsers` mid-batch"** — `batchCalculateUserLoyaltyLevels` freezes `userCount = _allUsers.length` on the first batch (L263–265); later appends are deferred to the next epoch. Sound.
5. **"Fixed-term interest self-heal at FixedTermDeposit.sol:469 mis-initialises `userTrancheSharesAfter` when neither branch fires"** — the `= trancheShares` default (the M-07 fix) is correct: it represents "no delta" and matches the stored value, so the `if (trancheShares != userTrancheSharesAfter)` at L489 correctly skips the write. Sound.
6. **"Reward-caps setter allows (0, non-zero) or (non-zero, 0)"** — both cases fail the `if (perUserCap == 0 || batchCap == 0) revert RewardCapsNotSet()` guard on entry. Effective pause. Sound.
7. **"`reportLoss` waterfall breaks when tranche[0] has pending loss mint"** — `registerTrancheLoss` has `notPendingLossMint` at LendingPoolTrancheLoss.sol:116, so `reportLoss` reverts entirely if *any* tranche touched in the loop has a prior pending mint. The loop never leaves a partial state. Sound.
8. **"`disableFeesForUser` double-counts rewards if called twice"** — guarded by `if (isFeeRecipientEnabled[user])` (KSULocking.sol:293). Second call is a no-op. Sound.

---

## Conclusion

The release-candidate branch holds up well under a full Feynman interrogation. All four recent fixes (M-03, M-04, M-06, M-08) achieve their stated goals. One genuine MEDIUM issue surfaces as a byproduct of the M-08 dust fix (FV-01): the fallback hands out the user's full share balance without capping it against the priority's remaining asset budget, which can cause step-4 clearing to over-commit against the pool's liquidity and wedge. Three LOW / informational items round out the report.

**No Critical or High findings.** With FV-01 patched (a ~10-line change), the branch is in good shape to ship.
