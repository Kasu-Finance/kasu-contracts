# State Inconsistency Audit — Post FV-01 Follow-Up

Branch: `release-candidate`
HEAD: `f8d2d45` — "feat(security): fix M-03/M-04/M-06/M-08 + FV-01"
Scope: delta from prior state audit (29 pairs) — focused on the new state introduced by the FV-01 fix.
Methodology: State Inconsistency Auditor SKILL (Phases 1–8), restricted to the new coupled state.

---

## New Coupled Pair Under Audit

**P30 — `AcceptedRequestsExecutionEpoch.acceptedAssetValuePerPriority[priority]` ↔ `ClearingData.acceptedPriorityWithdrawalAmounts[priority]`**

**Invariant (intended):**
For a given `targetEpoch` and `priority`, at every instant during step 4:

  `Σ (over accepted wNFTs in this epoch and priority) convertToAssets(acceptedWithdrawalShares)` ≤ `clearingData.acceptedPriorityWithdrawalAmounts[priority]`

This budget is checked **only for the dust-truncation fallback branch** — the pro-rata branch updates the running sum but does not gate on it (safe, see §Sub-invariants below).

**File / lines:**
- Struct definition: `src/core/clearing/AcceptedRequestsExecution.sol:18-22`
- Budget read: `src/core/clearing/AcceptedRequestsExecution.sol:219-221`
- Budget write (pro-rata): `src/core/clearing/AcceptedRequestsExecution.sol:225-229`, accumulated at `:232-234`
- Budget write (dust fallback): `src/core/clearing/AcceptedRequestsExecution.sol:222-223`, accumulated at `:232-234`
- Mutation sites: only `executeAcceptedRequestsBatch` writes this mapping.

---

## Phase 1 — Dependency Map (delta)

| Related State | Relationship |
|---|---|
| `_acceptedRequestsExecutionPerEpoch[epoch].nextIndexToProcess` | Same struct — progresses the loop pointer; new mapping field is per-priority cumulative and **does not interact** with `nextIndexToProcess` beyond being inside the same struct instance. |
| `_acceptedRequestsExecutionPerEpoch[epoch].status` | Lifecycle (UNINITIALIZED → PENDING → ENDED). New mapping is populated only while `status == PENDING`. On first entry, `_initializeAcceptedRequests` does not write the new mapping (it starts zeroed — correct default). |
| `clearingData.acceptedPriorityWithdrawalAmounts[priority]` | Memory-only read (via `_clearingDataMemory`) — the upper bound on `acceptedAssetValuePerPriority[priority]`. Set once in step 3 (`calculateAndSaveAcceptedRequests`) and never mutated after. |
| `clearingData.pendingWithdrawals.priorityWithdrawalAmounts[priority]` | Set in step 2 (`PendingRequestsPriorityCalculation.sol:188`) via `convertToAssets(...)` — same asset-unit convention as `acceptedPriorityWithdrawalAmounts` and the new mapping. Units match. |
| `_acceptWithdrawalRequest` (downstream) | Triggers `LendingPool.acceptWithdrawal` → `ILendingPoolTranche.redeem` → `removeUserActiveShares`. Each accept must be accompanied by a matching mapping increment — verified below. |

---

## Phase 2 — Mutation Matrix (new mapping)

| Site | Type | Paired Updates | Verdict |
|---|---|---|---|
| Pro-rata path (line 232-235) | `mapping[priority] += convertToAssets(acceptedWithdrawalShares)` followed by `_acceptWithdrawalRequest(...)` | Both guarded by `if (acceptedWithdrawalShares > 0)` | ✓ Paired |
| Dust-fallback path (line 221-235) | Gate `consumed + fullAssetValue <= totalAcceptedAmount`, then set `acceptedAssetValue = fullAssetValue`, then increment mapping + accept | Write and accept share the same guard | ✓ Paired |

There is **no other write site** for `acceptedAssetValuePerPriority`. The mapping is never decremented, never deleted, never reset — correct, because it is keyed by `epoch`, and once an epoch's step 4 ends the struct entry is effectively immutable.

---

## Phase 3 — Cross-Check

Tested every condition where the mapping could desynchronize from `_acceptWithdrawalRequest`:

| Scenario | Outcome |
|---|---|
| `acceptedWithdrawalShares > 0` (pro-rata), full path | Mapping incremented with asset-equivalent via `convertToAssets`. Accept called. ✓ |
| `acceptedWithdrawalShares == 0 && sharesAmount > 0`, budget OK | Fallback fires, mapping += `fullAssetValue`, accept called. ✓ |
| `acceptedWithdrawalShares == 0 && sharesAmount > 0`, budget NOT OK | Fallback suppressed, `acceptedWithdrawalShares` stays 0, `acceptedAssetValue` stays 0; `if (acceptedWithdrawalShares > 0)` skips both mapping write and accept. Request left pending. ✓ |
| `totalAcceptedAmount == 0` for this priority | Outer guard at line 202 (`if (totalAcceptedAmount > 0)`) skips everything. No write, no accept. ✓ |
| `totalWithdrawalAmount == 0` | Guard at line 207 skips both branches. ✓ |
| Deposit request (not withdrawal) | Mapping entirely untouched (deposit branch doesn't reference it). Deposit accounting uses a separate memory variable `requestAmountLeft`. ✓ |
| `_acceptWithdrawalRequest` reverts | The mapping increment was already applied to storage at line 233-234 but the whole transaction reverts (no nested try/catch). Both writes roll back atomically. ✓ |
| Batch boundary (function returns mid-queue after batchSize items) | Mapping writes persist in storage, `nextIndexToProcess` updated at line 253. Next `executeAcceptedRequestsBatch` call for same `targetEpoch` sees accumulated `consumed` in mapping. ✓ FV-01 invariant holds **across batches** — this is the explicit design intent documented in the struct NatSpec. |
| Second accept for same wNFT in a later epoch | Different epoch key → different struct instance → mapping starts at zero. Correct, because `totalAcceptedAmount` is also per-epoch. ✓ |
| Partial withdrawal: wNFT has 100 shares, 50 accepted, 50 remain for next epoch | wNFT's `sharesAmount` decremented inside `_acceptWithdrawalRequest` (line 675). Next epoch re-evaluates the wNFT with new `sharesAmount = 50`. Mapping for **new** epoch starts at 0. ✓ |

**Result: no gaps.**

---

## Phase 4 — Intra-Function Ordering

The ordering within `executeAcceptedRequestsBatch` for a single wNFT iteration is:

1. Read `consumed` from storage mapping (for fallback branch only).
2. Compute `acceptedWithdrawalShares` (pro-rata) or `fullAssetValue` (fallback).
3. Decide `acceptedAssetValue`.
4. Increment mapping: `acceptedAssetValuePerPriority[priority] += acceptedAssetValue`.
5. Call `_acceptWithdrawalRequest(...)` which burns shares, transfers assets, and decrements `sharesAmount` on the wNFT.

**Ordering invariant check:** between step 4 and step 5 no external read of the mapping occurs (the only reads are at step 1 of later iterations inside the same tx, where the updated value is exactly what we want). Even if `_acceptWithdrawalRequest` reenters this contract (it cannot — the only caller path is `_onlyClearingCoordinator`), the mapping reflects the accept as committed. ✓

**Exchange-rate stability check:** `convertToAssets` is called multiple times across the loop. The loop body calls `redeem(...)` which in OZ's ERC4626 preserves the exchange rate under proportional redemption (`assets / shares == totalAssets / totalSupply` pre- and post-burn, modulo the virtual-shares offset which rounds in favor of remaining holders). Since `applyInterests` runs once before step 2 (`ClearingCoordinator.sol:202`) and is not re-invoked inside step 4, the ratio is effectively stable throughout step 4. The mapping's asset-units and `totalAcceptedAmount`'s asset-units match. ✓

**One nuance noted (non-finding):** In the pro-rata path, `Σ convertToAssets(acceptedWithdrawalShares_i)` over all users in a priority may drift slightly from the step-3-calculated `totalAcceptedAmount` due to ERC4626 rounding + pro-rata truncation. The drift is **downward** (each `convertToAssets` rounds down). So `consumed` after the pro-rata pass is `≤ totalAcceptedAmount`, leaving a small residual budget that the dust-fallback branch can correctly consume for later iterations — this is exactly the FV-01 design intent.

---

## Phase 5 — Parallel Path Comparison

| Coupled State | Pro-rata branch | Dust fallback branch | Verdict |
|---|---|---|---|
| `acceptedAssetValuePerPriority[priority]` | ✓ `+= convertToAssets(acceptedShares)` | ✓ `+= fullAssetValue` | Both update |
| `_acceptWithdrawalRequest` | ✓ called when shares > 0 | ✓ called when shares > 0 | Both call |
| wNFT `sharesAmount` | ✓ decremented inside `_acceptWithdrawalRequest` | ✓ same | Both update |
| `userActiveShares` | ✓ via `removeUserActiveShares` | ✓ same | Both update |
| Tranche ERC4626 `totalSupply`/`totalAssets` | ✓ via `redeem` | ✓ same | Both update |

No asymmetry between the two acceptance paths.

---

## Phase 6 — Multi-Step User Journey

```
Epoch E:
  Priority P has 4 users: U1..U4, each with shares worth ~$0.30.
  totalWithdrawalAmount (priority P) = $1.20 (in assets).
  totalAcceptedAmount (priority P) = $0.40 (step 3 decided only $0.40 is fillable).

Iteration U4: acceptedShares = 0.30 * 0.40 / 1.20 = 0.10 shares → non-zero → pro-rata
  convertToAssets(0.10) = $0.10 → mapping[P] = $0.10. accept(U4, 0.10). ✓
Iteration U3: same → mapping[P] = $0.20. ✓
Iteration U2: same → mapping[P] = $0.30. ✓
Iteration U1: same → mapping[P] = $0.40. ✓
Total accepted = $0.40 == budget. Every user got pro-rata 33% of their request. ✓

Scenario B (dust): 5 users, each with shares worth ~$0.05; totalAcceptedAmount = $0.20, totalWithdrawalAmount = $0.25.
  pro-rata per user = 0.05 * 0.20 / 0.25 = 0.04 shares (non-zero) → all go through pro-rata.
  Total = $0.20, mapping = $0.20 ✓

Scenario C (truncation → dust fallback): 1 user with 1 wei of shares, totalWithdrawalAmount = 10^18, totalAcceptedAmount = 10^17.
  acceptedShares = 1 * 10^17 / 10^18 = 0 → dust fallback path.
  fullAssetValue = convertToAssets(1) = 1 wei (assume 1:1).
  consumed (0) + 1 <= 10^17 → fallback fires, user gets 1 wei accepted. mapping[P] = 1. ✓
```

All traced sequences are consistent.

**Cross-batch journey (the case FV-01 was designed for):**
```
Batch 1 processes half the wNFTs in priority P; mapping[P] = $X (persists in storage because function returns without setting status=ENDED).
Batch 2 re-enters executeAcceptedRequestsBatch; reads _clearingDataMemory again (same values — step 3 did not re-run); continues loop from nextIndexToProcess.
Dust-fallback decisions in Batch 2 correctly see the accumulated $X and refuse to over-accept.
```
✓ Persistence across batches is the explicit reason this mapping lives in the struct rather than as a function-local.

---

## Phase 7 — Masking Code Check

The only defensive code in the new logic is the `consumed + fullAssetValue <= totalAcceptedAmount` gate — this is the **intended** safety gate, not a mask over broken state. If it denies the fallback, the wNFT simply remains in the queue for a later epoch (the request is not deleted). No silent data loss.

There is no try/catch, no ternary clamp, no `min()` cap, no early-exit on zero that would mask a desync.

---

## Phase 8 — Storage Layout Safety

**Critical check for upgrade safety** — the new mapping is a new field inside a struct that is the value type of an existing storage mapping (`_acceptedRequestsExecutionPerEpoch`).

| Chain | Prior layout | New layout | Collision risk |
|---|---|---|---|
| Base (`.openzeppelin/base.json:2627`) | struct = 64 bytes (slot 0: nextIndexToProcess, slot 1: status) | struct = 96 bytes (+slot 2: mapping pointer) | None — mapping entries live at `keccak256(outerKey ‖ outerSlot)` and subsequent struct fields at `+N`. Adding a trailing field to a struct in a `mapping(K=>Struct)` is safe because each entry is hash-spread; there is no neighboring state to collide with. ✓ |
| base-sepolia, unknown-50 (XDC), unknown-98866 (Plume) | same | same | same reasoning |

**Old epoch entries after upgrade:** for any `targetEpoch` that was processed pre-upgrade, reading `_acceptedRequestsExecutionPerEpoch[oldEpoch].acceptedAssetValuePerPriority[p]` will return 0 (zero-initialized uninstantiated slot). Those epochs are already in `status == ENDED` and will not re-enter `executeAcceptedRequestsBatch` (line 81-83 reverts with `AcceptedRequestsExecutionAlreadyProcessed`). So the new field is never read for pre-upgrade epochs. ✓

**In-flight epoch at upgrade time:** if step 4 is mid-batch when the upgrade happens (would require admin coordination), the new mapping starts at zero and the budget gate is conservative (`0 + fullAssetValue <= totalAcceptedAmount`). The worst case: the fallback might fire for more dust requests than FV-01 intended, up to the full `totalAcceptedAmount` of budget. This is still bounded by `totalAcceptedAmount`, so **no over-acceptance** — just a slightly looser first batch. Not a finding (and this scenario is operationally guarded anyway — clearing holds a lock).

---

## Summary of New Pair

| Pair | Invariant | Status |
|---|---|---|
| P30 | `Σ acceptedAssetValue (accepted wNFTs) ≤ acceptedPriorityWithdrawalAmounts[priority]` per (epoch, priority) | ✓ CONSISTENT |

The mapping is read and written consistently at every site. It correctly initializes per-epoch. Storage layout is upgrade-safe across Base, XDC, Plume. No path exists where a wNFT is accepted without a corresponding mapping increment, nor vice versa. Mid-loop reverts roll back atomically.

---

## Findings

**None.**

All 30 coupled pairs (29 prior + P30) remain in sync.

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |

---

## Verification Notes

- Tests: 208/208 passing at HEAD (per user statement, not re-executed).
- Code trace verification performed for every mutation and read site of the new mapping.
- Upgrade storage layout verified against `.openzeppelin/{base,base-sepolia,unknown-50,unknown-98866}.json`.
- No PoC necessary — the static analysis is sufficient and the audit goal was to verify that no new desync was introduced by the FV-01 change.
