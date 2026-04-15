# Feynman Audit — Post-FV-01 Verified Findings

## Scope
- **Repo:** `/Users/kirilivanov/DEV/Kasu/kasu-contracts`
- **Branch:** `release-candidate`
- **HEAD:** `f8d2d45` ("feat(security): fix M-03/M-04/M-06/M-08 + FV-01 from April 2026 audit")
- **Language:** Solidity 0.8.23
- **Tests at HEAD:** 208 / 208 passing (`forge test` run locally during audit).
- **Mode:** Full Feynman re-run from scratch against the entire `src/core/**` + `src/locking/**` surface, with deepest scrutiny on `AcceptedRequestsExecution.sol` (FV-01 fix site) and the secondary fix sites in `UserLoyaltyRewards.sol`, `UserManager.sol`, `SystemVariables.sol`, and `LendingPoolTrancheLoss.sol`.

## Verification summary

| ID | Severity | Status | Title |
|----|----------|--------|-------|
| — | — | — | **No new Critical / High / Medium findings. FV-01 fix confirmed sound.** |
| INF-01 | INFO | Acknowledged | Struct-size growth of `AcceptedRequestsExecutionEpoch` requires OZ upgrades validation flag for any in-flight clearing at upgrade time |
| INF-02 | INFO | Acknowledged | Budget accounting drifts by O(virtual-offset) on small-totalSupply tranches — direction is conservative (tighter dust gate), never loose |

**Result: 0 Critical, 0 High, 0 Medium, 0 Low, 2 Informational.**

The FV-01 mapping-based budget tracking is correct in all cases I was able to construct, and it preserves the invariants that the prior audit missed. I did not find new issues introduced by the fix, nor anything previously missed that is ≥ Low severity.

The two Informational items below are design notes, not defects: they are documented so the deployer team knows what to watch for when upgrading Base mainnet.

---

## FV-01 fix — exhaustive verification

### The change

`src/core/clearing/AcceptedRequestsExecution.sol`:

```solidity
struct AcceptedRequestsExecutionEpoch {
    uint256 nextIndexToProcess;
    TaskStatus status;
    mapping(uint8 priority => uint256 assetSpent) acceptedAssetValuePerPriority; // NEW
}
```

Withdrawal branch rewritten (lines 200–238):
- Pro-rata path (`acceptedWithdrawalShares > 0`): after computing shares, also computes `acceptedAssetValue = tranche.convertToAssets(acceptedWithdrawalShares)` and adds it to the priority's running budget.
- Dust fallback path (`acceptedWithdrawalShares == 0 && sharesAmount > 0`): only fires if `consumed + convertToAssets(sharesAmount) <= totalAcceptedAmount`. Otherwise the dust request is left pending for a future epoch (same as pre-M-08 behaviour).

### Feynman interrogation

**Q1.1 (WHY) — Why do both paths update the budget?**
Because the budget is a single counter per priority across all batches of one epoch. If only the dust path wrote to it, a pro-rata-heavy first batch followed by a dust-heavy second batch would read `consumed = 0` in batch 2 and let the fallback run wild again. The double-write is necessary for cross-batch correctness. ✅

**Q1.2 (DELETE) — What if I delete the pro-rata path's `acceptedAssetValue += ...`?**
FV-01 returns exactly as the prior audit described it, just pushed one batch later: batches with pro-rata only consume budget in-memory; the next batch starts with `consumed = 0` and the dust fallback over-accepts. This confirms both writes are load-bearing. ✅

**Q1.4 (SUFFICIENT) — Is the dust gate `consumed + fullAssetValue <= totalAcceptedAmount` enough?**
Yes. The gate preserves the step-3 invariant `Σ dust-fallback-asset-value ≤ remaining-priority-budget`, so combined with the pro-rata consumption (which is bounded at `~totalAcceptedAmount` by the math of the pro-rata formula) the total drawn never exceeds the pool's budgeted liquidity for that priority. The solvency check in `AcceptedRequestsCalculation._verifyResult` (lines 452–457) was already written in asset terms, so the fix aligns the per-user execution with the per-epoch verification. ✅

**Q2.1 / Q2.2 (ORDER) — Ordering of the three mutations (budget write, redeem, NFT update).**

Inside the withdrawal branch, for each user processed:
1. `_acceptedRequestsExecutionPerEpoch[...].acceptedAssetValuePerPriority[prio] += acceptedAssetValue;` (line 234)
2. `_acceptWithdrawalRequest(userRequestNftId, acceptedWithdrawalShares);` (line 235) — which internally calls `lendingPool.acceptWithdrawal → tranche.redeem → removeUserActiveShares → _transferAssets(user, asset)`

Swap test: if the budget write happened AFTER `_acceptWithdrawalRequest`, a revert inside `_transferAssets` (USDC balance too low) would roll back the write anyway — functionally equivalent. If the redeem happened BEFORE the budget accounting, the tranche's exchange rate would have already drifted for the NEXT user's `convertToAssets` call, but the CURRENT user's `acceptedAssetValue` was computed pre-redeem, which is still internally consistent. No ordering vulnerability. ✅

**Q2.4 (MID-FUNCTION ABORT) — What state is left behind on revert?**

`executeAcceptedRequestsBatch` writes `nextIndexToProcess = i` OUTSIDE the loop (line 253). A mid-loop revert rolls back every in-loop storage write (budget, redeem, NFT burn), so the entire batch is retryable from the same `nextIndexToProcess` as before the batch started. The budget mapping does NOT accumulate partial writes on revert — Solidity reverts storage atomically. ✅

**Q3.1 (CONSISTENCY) — Dust vs pro-rata path consistency.**

Both paths:
- use the SAME tranche (`withdrawalNftDetails.tranche`) for `convertToAssets`
- use the SAME accumulator (`acceptedAssetValuePerPriority[withdrawalNftDetails.priority]`)
- write under the same condition (`acceptedWithdrawalShares > 0`)

The `acceptedAssetValue` variable is declared once outside the if/else, defaults to 0, and is only written in exactly one of the two branches. If neither branch fires (pro-rata=0 AND fallback-gate-fails), `acceptedAssetValue = 0`, `acceptedWithdrawalShares = 0`, and the outer `if (acceptedWithdrawalShares > 0)` skips both the budget write and the `_acceptWithdrawalRequest`. Consistent. ✅

**Q4.2 (EXTERNAL DATA) — Is `convertToAssets` trustworthy?**

Yes: `withdrawalNftDetails.tranche` is set when the wNFT is minted by `_requestWithdrawal`, which is only callable via `requestWithdrawal` (guarded by `verifyTranche`) or internal paths that also validate. All tranches are Kasu-deployed beacon proxies pointing at `LendingPoolTranche` — no user can inject a malicious tranche. `convertToAssets` is OZ ERC4626 with a 12-decimal virtual offset; it is non-reverting and monotone in its argument. ✅

**Q4.6 (AMOUNTS) — Edge values.**

- `sharesAmount = 0`: the outer `if (withdrawalNftDetails.sharesAmount > 0)` in the dust branch prevents division-by-zero; `acceptedWithdrawalShares = 0` means nothing happens and nothing is written. ✅
- `totalAcceptedAmount = 0`: outer `if (totalAcceptedAmount > 0)` at line 202 skips the entire priority. ✅
- `totalWithdrawalAmount = 0`: inner `if (totalWithdrawalAmount > 0)` at line 207 prevents division-by-zero. ✅
- `totalAcceptedAmount = totalWithdrawalAmount` (100% acceptance): pro-rata gives every user their full shares; no user hits the dust branch; budget consumption sums to `convertToAssets(Σshares) ≈ totalWithdrawalAmount = totalAcceptedAmount`. ✅
- `fullAssetValue == 0` (sharesAmount rounds to 0 assets at current ratio): gate passes trivially, dust fires with zero-asset transfer. Harmless — the redeem call mints 0 lending-pool tokens and moves 0 USDC. No over-acceptance. ✅
- `consumed + fullAssetValue` overflow: both operands are uint256 asset amounts bounded by `totalAssets(tranche) ≤ 2^128` in any realistic pool; no overflow. ✅

**Q5.1 (FIRST CALL) — First batch on a fresh epoch.**

`_acceptedRequestsExecutionPerEpoch[targetEpoch].status == UNINITIALIZED` → `_initializeAcceptedRequests` runs and sets `nextIndexToProcess` + `status = PENDING`. The new mapping `acceptedAssetValuePerPriority` is NOT explicitly cleared — but Solidity's default zero for mapping values IS the correct initial state (no budget consumed). ✅

**Q5.3 (TWICE IN SUCCESSION) — Same batch retried after a previous batch.**

Between batches, `_acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedAssetValuePerPriority[prio]` persists across transactions. Batch 2 reads the running total from batch 1 and continues accounting correctly. This is the load-bearing property that FV-01's prior Option A sketch missed ("running variable initialised to totalAcceptedAmount on the first touch of this priority in the batch") — the committed fix is the mapping-based approach, which is correct across batches, unlike a stack/memory variable which would have reset every call. ✅

**Q7.1 (EXTERNAL CALL REORDERING) — Swap the budget write and `_acceptWithdrawalRequest`?**

Tried: if `_acceptWithdrawalRequest` were called FIRST and then the budget write, a reentrancy during `tranche.redeem` → `removeUserActiveShares` → `_userManager.removeUserActiveTranche` → ??? could re-enter `executeAcceptedRequestsBatch` via the clearing coordinator. But:
1. `executeAcceptedRequestsBatch` is gated by `_onlyClearingCoordinator()` which checks `msg.sender == _clearingCoordinator`. The only way to re-enter is if the clearing coordinator itself calls back in, which it does not — its flow is strictly `step 4 → step 5` within one external call, no callbacks.
2. Even absent that guard, `UserManager.removeUserActiveTranche` does not make external calls back to the clearing pipeline.
3. `_transferAssets` is OZ `SafeERC20.safeTransfer` on USDC, which never reenters.

So the ordering is safe in both directions; the current order (budget-write first) is marginally better because it preserves the invariant before any external call, consistent with checks-effects-interactions. ✅

**Q7.7 (ACCUMULATED STATE) — Can accumulated state from multiple batches corrupt the invariant?**

Construction attempt: batch 1 processes 10 pro-rata users consuming 95% of budget; batch 2 processes 100 dust users. After batch 1, `consumed = 0.95 × totalAcceptedAmount`. In batch 2, for every dust user the gate `consumed + fullAssetValue <= totalAcceptedAmount` fails once `fullAssetValue > 0.05 × totalAcceptedAmount`, and only the first few dust users (whose asset value fits in the 5% remainder) are accepted. The rest roll over. Exactly the desired behaviour. ✅

### Storage-layout safety (critical upgrade concern)

**Prior on-chain layout (Base mainnet, per `.openzeppelin/base.json`):**

```json
"t_struct(AcceptedRequestsExecutionEpoch)16598_storage": {
  "members": [
    { "label": "nextIndexToProcess", "type": "t_uint256", "slot": "0" },
    { "label": "status",             "type": "t_enum",    "slot": "1" }
  ],
  "numberOfBytes": "64"
}
```

The struct currently occupies 2 slots per epoch. The new struct has 3 members (the third being a mapping), which occupies one additional slot per epoch.

**Why this is safe in terms of contract-level slots:**

`_acceptedRequestsExecutionPerEpoch` is declared as `mapping(uint256 => AcceptedRequestsExecutionEpoch)` at contract slot 2. Solidity stores the struct value at `keccak256(epochId . slot2)` — each struct instance has its own hashed base slot, so growing the struct does NOT shift any other contract-level variable (`_clearingDataPerEpoch` stays at slot 3 and so on). I verified this by checking the PendingPool storage layout in `.openzeppelin/base.json`: the only variable after `_acceptedRequestsExecutionPerEpoch` at slot 2 is `_clearingDataPerEpoch` at slot 3, and nothing on disk moves when the struct grows.

**Why this is safe for existing epoch data:**

Old epochs have `nextIndexToProcess` and `status` in slots 0–1 of their hashed base. The new slot 2 (mapping base) reads as all-zero for any old epoch. `acceptedAssetValuePerPriority[any]` reads as zero, which is the correct initial state (no budget consumed). Old completed epochs are in status `ENDED`, so the budget field is never consulted anyway. ✅

**Why the OZ upgrade plugin will still complain:**

Adding a struct member is a storage-layout change from the plugin's POV, even though the physical layout of every other variable is preserved. The upgrader must pass `unsafeAllow: ['struct-definition']` or use `forceImport` when running `upgradeProxy`. **This is the only operational catch.** See INF-01.

**Why it is safe for in-flight clearing:**

The only risk is an upgrade while step-4 is mid-batch for some active epoch. In that case, the in-flight epoch's struct has `nextIndexToProcess > 0` and `status = PENDING` at slots 0–1, but the new `acceptedAssetValuePerPriority` mapping reads as zero post-upgrade. Subsequent batches would start the priority budget "clean" without the accounting from already-processed requests — which means a dust-heavy epoch-in-progress at upgrade time could over-accept exactly as pre-FV-01. This is the same risk profile as rolling back to the un-patched code, and it self-heals the next epoch. Acceptable, since upgrades are done during a clearing window or before clearing starts (operational discipline is already in place for this pool: see CLAUDE.md "Deployment & Upgrade Workflow").

### Per-batch convertToAssets consistency check

I specifically worried about this: pro-rata uses `shares × totalAcceptedAmount / totalWithdrawalAmount`, but the budget accumulator uses `convertToAssets(shares)`. If the tranche's share ratio drifts between step-2 snapshot and step-4 execution, could the two accountings diverge in a way that breaks the invariant?

**Drift sources:**
- `applyInterests` runs BEFORE step 2 (ClearingCoordinator.sol:202). No further interest during step 4.
- `tranche.redeem` during step-4 execution itself: burns shares, transfers underlying. Ratio stays constant to first order; second-order drift from OZ's 12-decimal virtual offset is O(1 wei / (totalSupply + 1e12)) per redeem, bounded by users × 1 wei across the whole batch.
- No deposits, no new interest, no loss registration during step 4 (M-06 self-heal runs BEFORE the loop and reverts if not fully drainable).

**Drift direction:**

After `redeem(s, a)`, new ratio = (T - a + 1) / (S - s + 1e12). Prior ratio = (T + 1) / (S + 1e12). If `a/s ≈ (T+1)/(S+1e12)`, the new ratio is SLIGHTLY HIGHER (because a/s is the exchange rate and it increases marginally once s drops relative to the virtual offset). The drift is UPWARD — same shares buy slightly more assets for later users.

**Implication:**

Cumulative `Σ convertToAssets(accepted_i)` in step-4 time is SLIGHTLY LARGER than the step-2 snapshot `totalAcceptedAmount` for the priority. In practice the difference is a few wei per batch — absolutely negligible relative to any realistic `totalAcceptedAmount`, but directionally it means:

- Pro-rata accounting is slightly *over*stated → the dust gate is slightly *stricter* (more dust rolls over than strictly necessary).
- No over-acceptance is possible from this drift, since the dust gate is the only dispenser that can exceed the step-2 budget, and it reads a conservatively-inflated `consumed`.

So drift is in the safe direction. See INF-02.

### Verification: targeted PoC tests

The repo ships `test/unit/core/M08DustWithdrawalTest.sol` (263 lines) which plants a harness on the abstract `AcceptedRequestsExecution` contract, feeds it crafted `WithdrawalNftDetails`, and checks both the pro-rata and dust-fallback paths including cross-batch continuation. All 208 tests pass at HEAD `f8d2d45`. I inspected the harness — it uses a `Mock1to1Tranche` (convertToAssets returns shares as assets) so the budget arithmetic can be reasoned about exactly, and it exercises the exact scenario FV-01 was designed to cover (dust-heavy priorities, multi-batch, budget running out). ✅

---

## Broader re-audit — what else I looked at

I re-walked the four prior-round fixes, the full `src/core/**` tree, and the locking module, looking for anything new.

### Re-verification of M-03, M-04, M-06, M-08

**M-03 — `emitUserLoyaltyRewardBatch` reward caps.** Re-read the diff. `perUserCap == 0 || batchCap == 0` fails closed with `RewardCapsNotSet`. Per-user enforcement is after the internal `_emitUserLoyaltyReward` return, but any revert rolls back the state write inside that function (which updates `userRewards[user]` and `totalUnclaimedRewards` — both revert-scoped). Sound. Prior FV-04 (unvalidated `ksuTokenPrice` param) is still technically present but the caps bound the blast radius, and it is an acknowledged admin-trust concern.

**M-04 — ksuEpochTokenPrice freshness.** Three layers: (1) cron via `updateKsuTokenPrice`, (2) self-heal via `UserManager.batchCalculateUserLoyaltyLevels` → `_systemVariables.updateKsuEpochTokenPrice()`, (3) view fallback via `ksuEpochTokenPriceFresh`. The self-heal is idempotent (no-op when `priceUpdateEpoch == currentEpochNumber`). `_loyaltyParameters` now reads the fresh view. Sound; no issue I missed.

**M-06 — loss-mint self-heal in step 4.** At the very top of `executeAcceptedRequestsBatch` (lines 97–106), before any state is read. Per-tranche drain up to 100 users, reverts with explicit `LossMintingStillPending` if oversized. Combined with `notPendingLossMint` on `LendingPoolTranche.deposit` / `redeem`, the invariant "step 4 never touches a tranche with pending loss mints" is enforced. Sound. Checked that no tranche address in `_lendingPoolTranches()` can escape this loop (they all inherit the trancheloss base).

**M-08 — dust truncation fallback.** Fixed by FV-01 (above).

### Other areas re-walked — no new findings

I spent additional time looking for anything the prior rounds might have missed, and specifically re-read:

- `AcceptedRequestsCalculation._verifyResult` (the solvency invariant) — still correct, still asset-denominated, so the FV-01 budget tracking correctly mirrors it.
- `PendingRequestsPriorityCalculation._calculatePendingRequestsPriority` — uses `convertToAssets` at step-2 time to populate `priorityWithdrawalAmounts`, which is then the denominator for pro-rata in step-4. Since step-4 re-evaluates `convertToAssets` in-flight, and step-2 was the snapshot, the drift analysis in INF-02 is the only asymmetry.
- `LendingPool.acceptWithdrawal` — chain of `tranche.redeem → removeUserActiveShares → _burn → _transferAssets(user)`. Any failure at `_transferAssets` reverts the whole batch (good — preserves solvency). No reentrancy path.
- `PendingPool._requestWithdrawal / _acceptWithdrawalRequest` — untouched by the fix, still sound.
- `KSULocking`, `rKSU`, `KSULockBonus` — no changes in this commit. Not in scope.
- `FeeManager` / `ProtocolFeeManager` / Lite variants — no changes.
- `UserManager.batchCalculateUserLoyaltyLevels` — the new `updateKsuEpochTokenPrice()` call is idempotent. `_loyaltyParameters` correctly reads the fresh view.

Nothing turned up that exceeds Informational severity, and the previously-identified FV-02, FV-03, FV-04 remain as they were in the prior audit (they were not targeted by this commit).

---

## Informational items

### INF-01 — OZ upgrade plugin will flag the struct growth

**File:** `src/core/clearing/AcceptedRequestsExecution.sol`
**Lines:** 18–22

**What:** Adding a mapping field to `AcceptedRequestsExecutionEpoch` grows the struct from 2 → 3 slots. This is safe in terms of contract-level storage (verified against `.openzeppelin/base.json`), but the OZ upgrades plugin treats struct member additions as layout changes.

**What to do on upgrade:** Use `upgradeProxy(..., { unsafeAllow: ['struct-definition'] })` or equivalent hardhat-upgrades flag, and visually diff the PendingPool storage layout to confirm only the `AcceptedRequestsExecutionEpoch` inner struct changed and no contract-level slot shifted.

**Severity:** Informational — it is an operational note, not a bug.

### INF-02 — `convertToAssets` drift is directionally conservative

**Files:** `src/core/clearing/AcceptedRequestsExecution.sol` (budget accumulator), `src/core/clearing/PendingRequestsPriorityCalculation.sol` (step-2 snapshot).

**What:** Step 2 snapshots the asset value of pending withdrawals at pre-clearing share price. Step 4 re-evaluates `convertToAssets` on each user's accepted shares during the loop, and the tranche's share price drifts marginally upward as `tranche.redeem` burns shares (OZ 12-decimal virtual offset). The cumulative step-4 asset accounting is therefore slightly larger than the step-2 snapshot, and the dust gate is therefore slightly stricter than strictly necessary.

**Impact:** At most a few wei per batch of rollover-to-next-epoch for dust users who sit right at the budget boundary. No over-acceptance is possible from this direction. Not worth fixing unless an edge case materialises; worth documenting.

**Severity:** Informational — direction is safe; magnitude is noise.

---

## False-positive hypotheses checked and discarded

I generated and ruled out the following during the audit:

1. **"Pro-rata consumption can exceed totalAcceptedAmount via convertToAssets drift in the UNSAFE direction."** Ruled out: virtual offset makes the ratio monotonically non-decreasing as shares are burned, so drift is upward, not downward. The only way for sum-of-pro-rata to exceed `totalAcceptedAmount` would be if `convertToAssets` returned a LARGER value for each user than `shares × totalAccepted / totalWithdrawal` times the starting ratio, which it cannot by monotonicity.

2. **"Dust gate off-by-one: `<= totalAcceptedAmount` should be `<`."** Ruled out: `<=` means the last asset-denominated wei is spendable on dust. Since budgets are asset-valued and disbursements are asset-valued, equality is fine and preserves the invariant.

3. **"The new mapping key `uint8 priority` can overflow when `loyaltyLevelsCount + 1 > 255`."** Ruled out: `WithdrawalNftDetails.priority` is already `uint8` at the NFT-mint site. System config is not enforced against 256 but the realistic max loyalty levels configured in `SystemVariables` is well under 10. If someone did configure >255 levels, `PendingRequestsPriorityCalculation` would already be broken at NFT-mint, not at step 4.

4. **"Reentrancy through `tranche.convertToAssets`."** Ruled out: `convertToAssets` is a pure view on the tranche's total supply and total assets; no callbacks. (And the callee is a Kasu-deployed beacon proxy, not user-controllable.)

5. **"`_acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedAssetValuePerPriority` is never cleared across epochs."** Ruled out: the outer mapping key IS the epoch ID, so each epoch has its own inner mapping. No cross-epoch pollution.

6. **"The budget read `consumed` could be stale if two concurrent batches run."** Ruled out: `executeAcceptedRequestsBatch` is guarded by `_onlyClearingCoordinator`; the clearing coordinator is sequential. Solidity is single-threaded within a transaction. Cross-transaction, the storage read sees the committed state from the prior transaction. No concurrency.

7. **"FV-02 was supposed to be fixed — is it?"** Checked: `registerTrancheLoss` still allows the `_trancheUsers.length == 0` path (LendingPoolTrancheLoss.sol:113–128). Repaid funds into a zero-user loss are still trappable. This was LOW in the prior audit and remains unaddressed. Since it was not in scope of this commit, it is not a regression — but noting it here so nothing falls through the cracks.

---

## Conclusion

The FV-01 fix is correct, minimally invasive, and upgrade-safe modulo the OZ plugin advisory flag. I could not construct a scenario where the new budget tracking fails to prevent the over-acceptance the fix was designed to stop, nor one where it introduces new issues. Cross-batch correctness (the concrete thing a single in-memory counter would have gotten wrong) is handled by the mapping-in-struct extension.

The rest of the codebase at HEAD `f8d2d45` holds up. All four prior fixes (M-03, M-04, M-06, M-08) continue to behave as designed; the one previously-flagged LOW (FV-02, zero-user registerTrancheLoss) remains unaddressed as expected; no new issues surfaced.

**Recommended next step:** document INF-01 (OZ upgrades plugin flag) in the Base mainnet upgrade runbook, and proceed with the deployment when ready.
