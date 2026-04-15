# Nemesis Audit — Post-FV-01 Re-Audit
**Protocol:** Kasu Private Credit Lending
**Branch:** `release-candidate`
**Commit:** `f8d2d45` — M-03 / M-04 / M-06 / M-08 + FV-01 fixes landed.
**Date:** 2026-04-15
**Scope:** Focused on the FV-01 fix (`AcceptedRequestsExecution.executeAcceptedRequestsBatch`) and its interaction with the four April 2026 mediums. Prior passes' clearances for M-03 / M-04 / M-06 / M-08 were not re-traversed except where the FV-01 change path touches them.
**Passes run:** 4 (Feynman-full → State-full → Feynman-targeted → State-targeted). Converged — no new deltas on pass 4.
**Test state:** `forge test` — **208 / 208 passing**.

---

## Executive summary

FV-01 — running per-priority asset budget inside the extended `AcceptedRequestsExecutionEpoch` struct — is **SOUND**. It plugs the aggregate-dust over-acceptance gap without introducing new coupling bugs, reentrancy vectors, storage-layout regressions, or unit-mismatch errors. The ordering of "increment budget → call `_acceptWithdrawalRequest`" is safe: the increment is to private storage that no external caller reads, and `_acceptWithdrawalRequest` holds no path back into `executeAcceptedRequestsBatch` (the coordinator gate precludes reentry into step 4).

No regression in any of the previously cleared fixes (M-03, M-04, M-06, M-08).

### Fix verdict table

| Fix | Verdict |
|-----|---------|
| M-03 (reward caps) | **SOUND** (re-confirmed, no FV-01 interaction) |
| M-04 (stale-price self-heal) | **SOUND** (re-confirmed, no FV-01 interaction) |
| M-06 (loss-mint self-heal) | **SOUND** (re-confirmed; runs before FV-01 code path in same function — no coupling) |
| M-08 (dust withdrawal fallback) | **SOUND** (superseded by FV-01 which now bounds it per-priority) |
| FV-01 (per-priority asset budget) | **SOUND** |

### Finding counts

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
| Informational | 1 (storage layout — upgrade procedure check) |

Prior L-1 (`setRewardCaps` upper bound) and L-2 (M-06 gas on 3-tranche pools) from `nemesis-verified.md` remain open but unchanged. Prior I-1 (stale interface getter) remains open. No new L/M/H/C finding.

---

## FV-01 verification — evidence trail

### Surface

`src/core/clearing/AcceptedRequestsExecution.sol:18-22` — struct extension:

```
struct AcceptedRequestsExecutionEpoch {
    uint256 nextIndexToProcess;
    TaskStatus status;
    mapping(uint8 priority => uint256 assetSpent) acceptedAssetValuePerPriority;   // NEW
}
```

`AcceptedRequestsExecution.sol:207-236` — the budget-guarded fallback + pro-rata budget accounting.

### Feynman pass 1 — questions applied to the new code

**Q: What if the callee (`_acceptWithdrawalRequest` / `LendingPool.acceptWithdrawal` / `Tranche.redeem`) observes the half-updated budget?**
Traced: `acceptedAssetValuePerPriority` is `private`, accessed only inside `executeAcceptedRequestsBatch`. The call chain `_acceptWithdrawalRequest → LendingPool.acceptWithdrawal → Tranche.redeem` never reads this mapping. No external observer exists. The write-before-call ordering is safe even under a hypothetical reentrancy (which is precluded anyway by `_onlyClearingCoordinator` gate and absence of receiver hooks — `redeem` transfers USDC ERC20 with no callback).

**Q: If `_acceptWithdrawalRequest` reverts, does the budget increment leak?**
No — full transaction revert rolls back the storage write. Atomicity preserved.

**Q: Why is `acceptedAssetValue` in the pro-rata branch (line 225-230) NOT bounded by a budget check, but the dust-fallback branch IS?**
Rationale is sound: pro-rata allocations by construction sum (approximately) to `totalAcceptedAmount`; only the **fallback** can push the sum past budget (that's the FV-01 bug). Pro-rata still needs to INCREMENT the counter so that later dust-fallback iterations see the correct "consumed" value. Verified: that exact pattern is implemented.

**Q: Can the sum `Σ convertToAssets(acceptedWithdrawalShares_i)` in step 4 differ from step 2's snapshot `priorityWithdrawalAmounts`?**
Yes — ERC4626 with `_decimalsOffset = 12` introduces tiny ratio drift per redeem (`1e-12` share precision). But:
- Step 2 builds `priorityWithdrawalAmounts` via `convertToAssets(shares)` per tranche/priority (`PendingRequestsPriorityCalculation.sol:181-189`) AFTER `applyInterests` has run (coordinator line 202).
- Step 4 applies no further interest; the only mutation to tranche ratio is the loop's own `redeem` calls. With virtual shares at 10¹², each redeem shifts the ratio by <10⁻¹². Aggregate drift over millions of NFTs is still sub-wei USDC.
- Consequence: sum-of-actuals ≤ totalAcceptedAmount by a negligible amount. Budget headroom is slightly more generous than strictly needed, never less. No over-acceptance vector.

**Q: Can a malicious tranche with inflated `convertToAssets` break the budget?**
Out of trust model: `withdrawalNftDetails.tranche` is set at wNFT mint time, verified against `_lendingPoolTranches()`, and pools are created only by `ROLE_LENDING_POOL_CREATOR` via the factory. An attacker cannot substitute a malicious tranche. Even if they could, `convertToAssets` is a view, cannot reenter, and inflation only causes the user's own dust NFT to fail the budget check (denying them a withdrawal), not to exceed it.

**Q: Cross-batch-call behavior — does call N+1 see state written by call N correctly?**
Yes. `acceptedAssetValuePerPriority` is in storage; `+=` from call N is persisted. Call N+1 re-reads it via `_acceptedRequestsExecutionPerEpoch[targetEpoch].acceptedAssetValuePerPriority[priority]` on line 219-220. The `clearingData` memory snapshot (line 108) is re-created fresh each call from immutable step-2/3 output, so `totalAcceptedAmount` is the same across calls. Cross-call coupling is correct.

**Q: Storage-coupling between memory `clearingData` and storage `_acceptedRequestsExecutionPerEpoch` — any drift?**
`clearingData` is read as memory (line 108) from `_clearingDataMemory(targetEpoch)`, which sources from storage (`ClearingSteps._clearingDataPerEpoch`). That storage is frozen after step 3 ends; step 4 never writes it. The memory copy is a safe snapshot. No drift.

**Q: Can a user mint many dust wNFTs in a single priority to stress the budget accounting?**
Dust path contributes `convertToAssets(1)` ≈ 0 per NFT given `_decimalsOffset=12`. One million dust NFTs → < 1 micro-cent USDC of budget consumption. Attacker pays gas for 1M wNFTs to extract sub-cent value. Not exploitable.

**Q: Priority key (uint8) — off-by-one or overflow?**
Priority is bounded by system loyalty levels (≤ 10 in practice). Mapping key is uint8; no overflow. All sites use `withdrawalNftDetails.priority` consistently (lines 201, 204, 220, 234). No asymmetry.

### State pass 2 — coupling map (delta from prior verified)

| Coupled pair | Invariant | All mutators maintain? |
|---|---|---|
| `acceptedAssetValuePerPriority[p]` ↔ `_acceptWithdrawalRequest(...,shares)` actually delivered | sum-in-budget = sum-of-actual-asset-value (within ratio drift) | ✓ — every accept increments by `convertToAssets(acceptedShares)` using the exact same ratio the redeem will consume |
| Struct extension `AcceptedRequestsExecutionEpoch` ↔ outer mapping storage slots | adding mapping field to mapping-value struct cannot collide with other slots | ✓ — struct only referenced from `_acceptedRequestsExecutionPerEpoch`; field added at end; mapping base slot = `keccak256(k . (outerSlot + 2))`, distinct from all other storage |
| `nextIndexToProcess` ↔ iteration progression ↔ `status==ENDED` | terminal states set atomically | ✓ — no change from prior audit |

### State pass 4 — propagation of pass 3 findings

No new pass-3 findings to propagate. Pass 4 = no-op. Converged.

---

## Findings

### I-1 (new) — Struct field addition may require `unsafeAllowRenames` / validation bypass on upgrade

**Severity:** Informational
**Discovery path:** State pass 2 — storage layout coupling check.
**File:** `src/core/clearing/AcceptedRequestsExecution.sol:18-22`; `.openzeppelin/base.json` and per-chain layout files.

OpenZeppelin `hardhat-upgrades` validates struct-layout changes even for structs used only as mapping values. Adding the `acceptedAssetValuePerPriority` field to `AcceptedRequestsExecutionEpoch` will likely trigger a layout-check warning on `upgrades.upgradeProxy` of the PendingPool proxy (PendingPool inherits this contract via ClearingSteps).

**At runtime:** the change is storage-safe — mapping-in-struct extensions don't shift any contract-level slots (confirmed via the mapping-key derivation). The added field occupies a new slot derived from `keccak256(priority . (baseSlot + 2))`, which cannot collide with anything else.

**At upgrade time:** the hardhat-upgrades plugin may refuse the upgrade unless `unsafeAllow: ['struct-definition']` or a similar flag is passed, **or** the layout file is pre-updated.

**Recommendation:**
1. Run `npx hardhat run scripts/<planned-upgrade>.ts --network base --dry-run` to observe whether the plugin flags this.
2. If flagged, either (a) update `.openzeppelin/<network>.json` layout entries manually and re-run, or (b) pass `unsafeAllow` with documentation that the slot derivation is safe.
3. No on-chain action is needed for the struct extension itself — this is a tooling-level concern only.

Prior `.audit/deployment-plan-2026-04.md:24` already notes this.

---

## Coverage notes

- `forge test` — 208 / 208 passing (1 new test in `M08DustWithdrawalTest.sol` specifically exercises the dust fallback; the pro-rata budget path is exercised implicitly by the full clearing test suite).
- The new budget path is NOT directly unit-tested for the pro-rata increment → fallback rejection sequence (i.e. a priority where pro-rata consumes the full budget and a subsequent dust NFT is denied). Adding such a test would improve regression protection. Not a bug — a coverage gap.
- Prior findings re-checked:
  - L-1 (`setRewardCaps` no upper bound) — no change, still open as defense-in-depth.
  - L-2 (M-06 gas on 3-tranche pools) — no change.
  - I-1 prior (`ksuEpochTokenPrice()` stale interface getter) — no change.

## Pass delta summary

| Pass | New findings |
|---|---|
| 1 (Feynman-full on FV-01 path) | 0 findings, 0 new suspects |
| 2 (State-full on FV-01 path + extended struct) | 1 informational (upgrade tooling) |
| 3 (Feynman-targeted on pass-2 informational) | 0 (no logic bug behind the tooling note) |
| 4 (State-targeted — none to propagate) | 0 |

**Converged after pass 4.**
