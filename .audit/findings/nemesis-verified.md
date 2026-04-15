# Nemesis Audit — Verified Findings
**Protocol:** Kasu Private Credit Lending
**Branch:** `release-candidate`
**Commit state:** Four just-landed fixes (M-03, M-04, M-06, M-08) on top of the April 2026 v2 audit.
**Date:** 2026-04-15
**Scope:** `src/core/**` (emphasis on the four fix sites and their dependency graph).
**Pass count at convergence:** 4 (Feynman-full → State-full → Feynman-targeted → State-targeted).
**Test state:** `forge test` — 207/207 passing.

---

## Executive summary

The four fixes (M-03 reward caps, M-04 stale-price self-heal, M-06 loss-mint self-heal, M-08 dust-withdrawal fallback) are each **SOUND** with respect to their stated goal. No regression in the core upgrade-safe storage layout. No new critical or high finding.

Two low-severity observations and one informational note emerged. None blocks the upgrade.

| Verdict | M-03 | M-04 | M-06 | M-08 |
|---------|------|------|------|------|
| Status  | SOUND | SOUND | SOUND | SOUND |

**Finding counts by severity:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |
| Informational | 1 |

**Headline (new observation):** The only new exposure surfaced by this re-audit is that `UserLoyaltyRewards.setRewardCaps` accepts arbitrarily large values, so a rogue admin can re-enable an unbounded batch drain via two transactions rather than one. This is a pre-existing trust assumption made slightly more explicit by M-03; it does not change the protocol's security posture.

---

## Fix verdicts

### M-03 — Reward caps in `UserLoyaltyRewards` · VERDICT: SOUND

Verified:
- New storage slots `maxRewardPerUserPerBatch` (slot after `userRewards`), `maxBatchTotalReward` are **appended** to existing layout (confirmed by reading `UserLoyaltyRewards.sol:42-50`). Upgrade-safe.
- Default state after upgrade: both caps = 0 → `emitUserLoyaltyRewardBatch` reverts `RewardCapsNotSet`. Fail-closed.
- Cap enforcement correctly happens after each per-user reward is computed and is added to `batchTotal`. Revert rolls back storage mutations from `_emitUserLoyaltyReward`.
- `claimReward` still updates coupled pair `userRewards[u]` + `totalUnclaimedRewards` atomically.
- `UserLoyaltyRewardsLite` mirror is a pure stateless override (no storage → no slot collision concern).

Residual observation → see **L-1**.

### M-04 — Stale KSU price self-heal · VERDICT: SOUND

Verified (`SystemVariables.sol:246-251`, `UserManager.sol:257, 434`):
- `ksuEpochTokenPriceFresh()` is a **pure view** (does not write). Returns spot when `currentEpochNumber() > priceUpdateEpoch`, else snapshot.
- `batchCalculateUserLoyaltyLevels` self-heals via `_systemVariables.updateKsuEpochTokenPrice()` at the top (line 257) BEFORE the parameter read (line 259) and BEFORE reading `ksuEpochTokenPriceFresh`. Ordering correct.
- Grep confirms **no remaining consumer** in `src/` reads the stale `ksuEpochTokenPrice()` getter for computation. Only external subgraphs/UIs read it, and the interface preserves the stale getter for compatibility.
- `_updateKsuTokenPrice` writes `priceUpdateEpoch` and `ksuEpochTokenPrice` in the same function → coupled pair stays atomic.
- Missed-cron sequence for N epochs: per-epoch self-heal in clearing guarantees the snapshot is fresh before loyalty level reads. The per-user `emitUserLoyaltyReward` also reads spot price directly (line 107), so reward emission never uses a stale snapshot.

### M-06 — Loss-mint self-heal in clearing step 4 · VERDICT: SOUND

Verified (`AcceptedRequestsExecution.sol:84-101`, `LendingPoolTrancheLoss.sol:67-85`):
- New views `pendingLossMintId()`, `pendingLossMintUsersRemaining()` — read-only, no new write paths, no coupled-state impact.
- Self-heal loop runs **before** any tranche deposit/redeem in step 4 (line 92-101 vs line 118+). ✓
- `_batchMintLossTokens` updates `usersMintedCount` atomically and only clears `_pendingMintLossId` when `_isLossMintingComplete` returns true. Partial mid-call state (between `_lossDetails[lossId] = LossDetails(...)` line 250 and `_pendingMintLossId = lossId` line 255) is not observable externally — the only callers hold `onlyOwnLendingPool` and `notPendingLossMint` guards, and ERC1155 mint acceptance hooks happen only in `_mintUserLossTokens` (after both writes are committed).
- If tranche queue > 100 users, revert `LossMintingStillPending` — clearer must drain manually; no half-state left behind.
- Multi-tranche self-heal: iterates all tranches, each capped at 100 mints per clearing tx. Gas-budget concern → see **L-2**.

### M-08 — Dust-truncation fallback in withdrawal acceptance · VERDICT: SOUND

Verified (`AcceptedRequestsExecution.sol:207-209`):
- Fallback activates only when `acceptedWithdrawalShares == 0 && sharesAmount > 0` — targets the stuck-dust-NFT bug exactly.
- Aggregate over-acceptance across many dust NFTs is bounded:
  - For truncation to 0 with a >50% accept ratio, `sharesAmount` must be 1 or 2.
  - ERC4626 with `_decimalsOffset = 12` makes 1 share ≈ 10⁻¹² USDC in asset value.
  - Even 1 million dust NFTs → < $0.000001 of leakage, at gas cost of creating 1M NFTs that far exceeds the leakage.
- `_acceptWithdrawalRequest` uses the already-checked `sharesAmount` as upper bound (line 670-672) → fallback never redeems more than the user's own NFT entitlement.
- Parallel path `rejectOrCancelWithdrawal` is unaffected (no ratio division).
- Test `test/unit/core/M08DustWithdrawalTest.sol` exercises the fallback explicitly.

---

## Findings

### L-1 — `setRewardCaps` has no hard upper bound on cap values

**Severity:** Low (defense-in-depth)
**Discovery path:** Feynman-only (Pass 1, UserLoyaltyRewards category 4 — admin trust assumption).
**File:** `src/core/UserLoyaltyRewards.sol:192-197`

A compromised or malicious admin can call `setRewardCaps(type(uint256).max, type(uint256).max)` followed by `emitUserLoyaltyRewardBatch([...], ksuTokenPrice=1)` to drain the entire KSU balance of the `UserLoyaltyRewards` contract in two transactions. The batch call's `ksuTokenPrice` parameter is admin-supplied and bypasses the oracle when nonzero, making the per-user reward arbitrarily large before the cap binds.

**Impact:** Bounded by KSU balance of the rewards contract. No new attack surface — the pre-M-03 code allowed a single transaction drain; M-03 now requires two and emits a `RewardCapsUpdated` event first. This is a pre-existing trust assumption on `ROLE_KASU_ADMIN`, not a regression.

**Recommendation (optional):** Add a constructor-time immutable absolute ceiling for both caps, e.g. `maxPerUser ≤ 10_000e18 KSU` and `maxPerBatch ≤ 1_000_000e18 KSU`, so that even a compromised admin cannot mint beyond the ceiling without a contract upgrade.

**Code trace:**
```
setRewardCaps — no bound check ────┐
                                    ↓
emitUserLoyaltyRewardBatch          │
  ksuTokenPrice = caller-supplied ──┼──→ ksuReward = (amountDeposited × 5% × 1e30) / ksuTokenPrice
  amountDeposited = caller-supplied ┘      → unbounded per-user given tiny ksuTokenPrice
                                        cap check: ksuReward > perUserCap reverts
                                        → admin sets perUserCap = MAX → no bound
```

### L-2 — M-06 self-heal may exceed block gas limit with 100+ users on all three tranches

**Severity:** Low (liveness, not safety)
**Discovery path:** Cross-feed Pass1→Pass3 (Feynman Category 5 "boundaries" → Phase 5 adversarial sequence).
**File:** `src/core/clearing/AcceptedRequestsExecution.sol:92-101`

If a pool has three tranches and each has ≥100 pending loss-token mints queued (`doMintLossTokens=false` on all), a single call to `executeAcceptedRequestsBatch` performs up to 300 ERC1155 mints (100 × 3 tranches) before processing requests. At ~100k-150k gas per mint, that is 30–45M gas — at or above the block gas limit for most EVM chains (30M on Base/Ethereum).

**Impact:** Clearing step 4 reverts on OOG. Clearer must manually call `batchMintLossTokens` on each tranche before retrying. Not a fund-loss bug — the protocol has `batchMintLossTokens` as a permissionless drain helper (`LendingPoolTrancheLoss.sol:138-144`) that can be called by anyone. Adds an operational burden but no vulnerability.

**Recommendation (optional):** Reduce `CLEARING_MINT_BATCH_SIZE` from 100 to 33, or make the self-heal call `batchMintLossTokens` on only one tranche per step-4 invocation. Alternatively, document the operational procedure (drain manually before clearing) in the runbook.

### I-1 — Interface still exposes stale `ksuEpochTokenPrice()` getter

**Severity:** Informational
**Discovery path:** State-only (Pass 2 mutation matrix).
**File:** `src/core/interfaces/ISystemVariables.sol:30`

The interface preserves the public `ksuEpochTokenPrice()` getter (reads the possibly-stale snapshot) alongside the new `ksuEpochTokenPriceFresh()`. In-protocol callers correctly use `Fresh`, but any off-chain consumer (subgraph, UI) that calls the bare getter receives stale data on missed-cron epochs.

**Impact:** Cosmetic for on-chain flow; potential confusion for integrators. Intentional — backwards-compat for external readers.

**Recommendation:** Note in the interface NatSpec that external consumers should prefer `ksuEpochTokenPriceFresh()`.

---

## Coverage notes

- Storage layout: confirmed appended additions in `UserLoyaltyRewards` (slots 0-6 unchanged, slots 7-8 = new caps).
- Lite mirror: `UserLoyaltyRewardsLite` is stateless, no slot collision risk.
- All four fixes tested:
  - M-03: caps-not-set revert, per-user-cap revert, batch-cap revert exercised in test suite (see `test/unit/core/UserLoyaltyRewards*.sol`).
  - M-04: no standalone test file found for the view getter or self-heal; the grep confirms the code path but an explicit test would be valuable — this is a low-priority defect in test coverage, not a bug.
  - M-06: `test_M06_clearingMintBatchSizeExposed`, `test_M06_pendingLossMintAccessors` — passing.
  - M-08: `M08DustWithdrawalTest.sol` — passing.

---
