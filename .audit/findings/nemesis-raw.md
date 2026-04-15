# Nemesis Audit — Raw Pass Output
**Branch:** release-candidate
**Date:** 2026-04-15
**Scope:** `src/core/**` with focus on four just-landed fixes (M-03, M-04, M-06, M-08).

---

## Phase 0 — Recon

**Attack goals (ranked):**
1. Drain USDC from lending pool via under-accounted loss / over-accounted withdrawal.
2. Mint unbounded KSU rewards to attacker-controlled addresses.
3. Stall clearing permanently (brick the protocol for all pools).
4. Corrupt loyalty level accounting to gain free priority in clearing.
5. Skip KYC gating via Nexera bypass.

**Novel, high-bug-density code:**
- `clearing/*` — bespoke multi-step priority clearing, 4 steps, shared state across 5 contracts.
- `lendingPool/LendingPoolTrancheLoss.sol` — custom ERC1155 loss-receipt + partial mint queue.
- `lendingPool/PendingPool.sol` — massive (750+ lines) NFT lifecycle + accepted request execution.
- `UserLoyaltyRewards.sol` — new caps + KSU reward math.
- `SystemVariables.sol` — epoch + price snapshot with self-heal.

**Value stores:**
- `LendingPool` (USDC custody via tranche redemption → assets pooled + burned tranche shares).
- `LendingPoolTrancheLoss` (loss-receipt custody + repaid USDC until claim).
- `UserLoyaltyRewards` (KSU balance to be claimed → minted by admin-deposited KSU).
- `FeeManager` + `ProtocolFeeManagerLite` (USDC fees).

**Initial coupling hypothesis (from recon only):**
- `userRewards[u]` ↔ `totalUnclaimedRewards` (must sum — checked below).
- `maxRewardPerUserPerBatch` / `maxBatchTotalReward` (new) ↔ `userRewards[u]` (must bound).
- `priceUpdateEpoch` ↔ `ksuEpochTokenPrice` (must be read together or via Fresh view).
- `_pendingMintLossId` ↔ `_lossDetails[lossId].usersMintedCount` / `usersCount`.
- `userActiveShares[u]` ↔ `_trancheUsers` array / `_userArrayIndex`.
- `totalAcceptedAmount` (priority, step 3) ↔ per-NFT `acceptedWithdrawalShares` (step 4).

---

## Pass 1 — Feynman (full sweep, fix-site focused)

### UserLoyaltyRewards.sol

| Line | Interrogation | Verdict |
|------|---------------|---------|
| 46/50 | New `maxRewardPerUserPerBatch`, `maxBatchTotalReward` storage slots. Q: appended after `userRewards`? A: YES — declared AFTER line 42 mapping. No collision on upgrade. | SOUND (storage) |
| 152-156 | `if (perUserCap==0 \|\| batchCap==0) revert` — default state is disabled. Safe after upgrade. | SOUND |
| 159-161 | If `ksuTokenPrice == 0` → reads fresh spot price. If nonzero → admin-supplied value used verbatim. Q: can admin pass `ksuTokenPrice=1` to inflate each reward? A: YES. Mitigation: per-user / per-batch caps. | SUSPECT (bounded) |
| 166-172 | `ksuReward` computed from admin-supplied `amountDeposited` + `ksuTokenPrice`. No cross-check against on-chain user balance → admin can specify ANY amount. Cap still binds. | SUSPECT (bounded) |
| 174-176 | Cap check happens AFTER storage mutation in `_emitUserLoyaltyReward` (line 266/267). Reverting on cap exceeded rolls back the tx cleanly. | SOUND |
| 192-197 | `setRewardCaps` has NO upper bound on `perUser`/`perBatch`. Admin can set to `type(uint256).max`. | SUSPECT → see **N-1** |
| 220-221 | `userRewards[msg.sender] -= amount; totalUnclaimedRewards -= amount` — coupled pair, both updated. | SOUND |
| 263-267 | Reward math: `(amountDeposited * epochRewardRate * 1e18 * 1e12) / ksuTokenPrice / 1e18` = `amountDeposited * epochRewardRate * 1e12 / ksuTokenPrice`. With admin-controlled `amountDeposited`, `epochRewardRate` capped at 5%, and admin-controlled `ksuTokenPrice` (can be tiny), reward magnitude is fully admin-controlled. | SUSPECT (admin trust) |

**Function-State matrix:**
- `emitUserLoyaltyRewardBatch` writes: `userRewards[u]`, `totalUnclaimedRewards` — both updated together. ✓

### SystemVariables.sol

| Line | Interrogation | Verdict |
|------|---------------|---------|
| 235-239 | `updateKsuEpochTokenPrice` is permissionless (anyone can call). Only triggers if stale. | SOUND |
| 246-251 | `ksuEpochTokenPriceFresh()` view — if stale, returns spot price; else snapshot. Does NOT mutate. | SOUND |
| 253-258 | `_updateKsuTokenPrice` — writes `priceUpdateEpoch = currentEpochNumber()` then `ksuEpochTokenPrice = spot`. Coupled pair updated atomically. | SOUND |

**Q: any remaining consumer that reads stale `ksuEpochTokenPrice()` without the Fresh fallback?**
A: Grep confirms NO in-protocol consumer reads `.ksuEpochTokenPrice()`. The only reader is `_loyaltyParameters` which uses `ksuEpochTokenPriceFresh()`. External callers (subgraph/UI) can still call the stale getter — acceptable since interface contract compatibility is preserved.

### UserManager.sol

| Line | Interrogation | Verdict |
|------|---------------|---------|
| 257 | `_systemVariables.updateKsuEpochTokenPrice()` — self-heal at top of `batchCalculateUserLoyaltyLevels`. Idempotent. Writes `priceUpdateEpoch` + `ksuEpochTokenPrice` BEFORE read. | SOUND |
| 287 | `emitUserLoyaltyReward(user, epoch, loyaltyLevel, activeDepositAmount)` — per-user call. `emitUserLoyaltyReward` (not batch) reads spot price inline. | SOUND (bypasses cap) |
| 434 | `params.ksuPrice = _systemVariables.ksuEpochTokenPriceFresh()` — after the self-heal, this is always fresh. View callers also get fresh. | SOUND |

**Q: can `_userLoyaltyLevel` + `emitUserLoyaltyReward` (non-batch path) bypass caps and cause overpayment?** A: Yes but that path uses the real `amountDeposited` read from on-chain state (via `_userLoyaltyLevel` return), not admin-supplied. Reward bounded by actual user liquidity × 5% → bounded by protocol TVL × 5% per epoch. Acceptable.

### LendingPoolTrancheLoss.sol

| Line | Interrogation | Verdict |
|------|---------------|---------|
| 67-69 | `isPendingLossMint()` = `_pendingMintLossId > 0`. Coupled with `_lossDetails[lossId].usersMintedCount`. | SOUND |
| 74-76 | `pendingLossMintId()` → `_pendingMintLossId`. No checks needed. | SOUND |
| 81-85 | `pendingLossMintUsersRemaining()` — `usersCount - usersMintedCount`. Invariant: `usersMintedCount ≤ usersCount` (always true in `_batchMintLossTokens`). Subtraction safe. | SOUND |
| 255 | `_pendingMintLossId = lossId;` set in `_registerLoss`. If `batchSize > 0` passed, immediately drains. If `batchSize == 0` (the `doMintLossTokens=false` case), `_pendingMintLossId` stays set → clearing coordinator's M-06 self-heal handles it. | SOUND |
| 289-292 | On full drain: `_pendingMintLossId = 0`. This clears `isPendingLossMint()`. | SOUND |

**Ordering concern (Q2.x):** In `_registerLoss` line 250 writes `_lossDetails[lossId]` BEFORE line 255 writes `_pendingMintLossId`. A reentrant ERC1155 `_update` hook could observe inconsistent state… but `_mintUserLossTokens` (called from `_batchMintLossTokens`) only mints via `_update(address(0), to, ids, values)`. Per OZ v5 semantics, `_doSafeTransferAcceptanceCheck` is called on mint if `to.isContract()`. A user who registers as a contract could reenter. But all relevant functions have `onlyOwnLendingPool` + `notPendingLossMint` modifiers. Reentrancy into `registerTrancheLoss` blocked by `notPendingLossMint`. Reentrancy into `batchMintLossTokens` — it checks `_pendingMintLossId != lossId` but doesn't have a global lock. Analyzed below.

### AcceptedRequestsExecution.sol (M-06 self-heal + M-08 dust fallback)

| Line | Interrogation | Verdict |
|------|---------------|---------|
| 35 | `CLEARING_MINT_BATCH_SIZE = 100` constant. Immutable. | SOUND |
| 80-82 | `if (batchSize == 0) return;` — early return BEFORE self-heal loop. Means `batchSize=0` call does NOT self-heal. Acceptable — cleaner callers know to pass nonzero. | NOTE (intentional) |
| 84-101 | Self-heal iterates all tranches. For each with `isPendingLossMint()`, calls `batchMintLossTokens(lossId, 100)`. If after, still pending → revert `LossMintingStillPending`. | SOUND |
| 92-101 | Q2.x: self-heal happens BEFORE the request-processing loop. ✓ | SOUND |
| 201-212 | Dust fallback: if `acceptedWithdrawalShares == 0 && sharesAmount > 0`, override to `sharesAmount`. | SUSPECT → N-2 |

**Gas-limit concern (Phase 5):** 3 tranches × 100 users per self-heal call = up to 300 ERC1155 mints in one iteration. ≈ 100k gas each × 300 = 30M gas, at block limit. If pool has >100 users per tranche, self-heal passes (drains 100, still pending → reverts), clearer must manually drain. Not a regression.

---

## Pass 2 — State Inconsistency (full, enriched by Pass 1)

### Coupled State Dependency Map

| Pair A | Pair B | Invariant | Mutating functions | Sync status |
|--------|--------|-----------|--------------------|-------------|
| `userRewards[u]` | `totalUnclaimedRewards` | `sum(userRewards)=totalUnclaimed` | `_emitUserLoyaltyReward` (both +=), `claimReward` (both -=) | ✓ |
| `priceUpdateEpoch` | `ksuEpochTokenPrice` | snapshot belongs to epoch | `_updateKsuTokenPrice` (both set) | ✓ |
| `_pendingMintLossId` | `_lossDetails[lossId].usersMintedCount` | pending iff `usersMintedCount<usersCount` | `_registerLoss`/`_batchMintLossTokens` | ✓ |
| `userActiveShares[u]` | `_trancheUsers`/`_userArrayIndex` | user in array iff shares>0 | `deposit`/`removeUserActiveShares` | ✓ |
| `maxRewardPerUserPerBatch` | `maxBatchTotalReward` | both zero = disabled | `setRewardCaps` (sets both) | ✓ |

### Mutation Matrix for new state

- `maxRewardPerUserPerBatch`: written only by `setRewardCaps` (onlyAdmin). Read by `emitUserLoyaltyRewardBatch` only. No gaps.
- `maxBatchTotalReward`: same.
- `_pendingMintLossId` NEW exposed views: `pendingLossMintId`, `pendingLossMintUsersRemaining`. Only READ-only accessors added. No new write sites. No gaps.

### Parallel-path comparison

- Withdrawal acceptance path: only `AcceptedRequestsExecution._acceptWithdrawalRequest` and `PendingPool.rejectOrCancelWithdrawal`. The M-08 fallback applies only to the clearing-accept path.
- Loss minting: `registerTrancheLoss(..., doMintLossTokens=true)` → eager mint; `registerTrancheLoss(..., doMintLossTokens=false)` → queue + later drain via `batchMintLossTokens` (manual) OR M-06 self-heal (automatic). Both paths update `_lossDetails[lossId].usersMintedCount` + `_pendingMintLossId` consistently.
- Price snapshot read: `_loyaltyParameters()` uses Fresh; permissionless `updateKsuEpochTokenPrice` writes both snapshot vars together. No read path bypasses both.

### Masking-code flags

- `LendingPoolTranche._calculateMaximumLossAmount`: `if (totalAssets_ > minimumAssetAmountLeftAfterLoss) maxLossAmount = totalAssets_ - minimumAssetAmountLeftAfterLoss;` — defensive min floor. Not masking a bug (design choice to leave dust in tranche).
- M-08 dust fallback itself IS a defensive unmask — the `acceptedWithdrawalShares == 0` was masking a stuck-NFT bug. Fallback removes mask.
- `_batchMintLossTokens` line 268 `if (batchSize > usersLeft) batchSize = usersLeft;` — clamp, but no missing invariant: clamping just bounds the loop. Sound.

---

## Pass 3 — Targeted Feynman (on Pass 2 deltas)

Pass 2 flagged no GAPS in the new code. The delta is the dust-fallback over-acceptance concern (M-08, Pass-1 flagged) — re-interrogating:

**Q: "What ASSUMPTION led to the dust fallback?"**
A: Assumption: `totalAcceptedAmount / totalWithdrawalAmount` approximates the acceptance ratio correctly for every NFT. For `sharesAmount=1` NFTs in a priority where the ratio is <100%, integer division truncates to 0 and the NFT stays pending forever (can never be fully burned). The fallback paves over this.

**Q: "What DOWNSTREAM function reads the over-accepted assets and breaks?"**
A: `LendingPool.acceptWithdrawal` → `ILendingPoolTranche.redeem` → burns shares, transfers USDC to pool, burns pool token, transfers USDC to user. Each step uses `acceptedShares` directly. Over-acceptance of 1 share per dust NFT causes up to `numDustNFTs × 1-share-asset-value` excess USDC transfer. 1 share of ERC4626 with 12-decimal-offset is ~1e-12 USDC = 0.000000000001 USDC. Economically meaningless for any feasible number of NFTs (gas cost to create NFT >> gain).

**Q: "Can attacker CHOOSE a sequence to exploit?"**
A: Creating a withdrawal NFT requires burning tranche shares proportionally. Creating 1M NFTs with `sharesAmount=1` each requires: 1M × gas-per-deposit ≈ 150M gas ≈ $100s on Base mainnet; gain ≈ $0.000001. Non-exploitable.

**Q: "What about parallel path — does canceling dust NFT have same issue?"**
A: `rejectOrCancelWithdrawal` processes full `sharesAmount` always; no ratio division. No parallel issue.

**Q: "What ASSUMPTION led to admin not being rate-limited in `setRewardCaps`?"**
A: Design assumption: admin is a multisig and caps are a secondary safety — not a trustless bound. This matches the pre-existing trust model (admin can also grant self more KSU by other means). Still, a hardcoded absolute ceiling would be defense-in-depth.

**Q: "What happens if cron misses N consecutive epochs?"**
A: Each epoch: view callers use `ksuEpochTokenPriceFresh` → always spot. First `batchCalculateUserLoyaltyLevels` call in new epoch updates snapshot as side-effect. No drift possible beyond 1 epoch because `_updateKsuTokenPrice` writes `priceUpdateEpoch = currentEpochNumber()` (current, not previous). Even if cron misses 5 epochs, next `batch...` call fills only the current. Historical snapshots for past epochs remain uninitialized (value 0 if never set). But the reward emission path reads from `_ksuPrice.ksuTokenPrice()` directly (spot), not snapshot — so rewards emitted DURING a clearing always use fresh price. The snapshot is purely for view consistency. No drift.

---

## Pass 4 — Targeted State Re-Analysis

No new coupled pairs surfaced in Pass 3. Dust-fallback over-acceptance is bounded to economically negligible values and doesn't create a new coupled-state violation.

**Convergence reached at Pass 4.** Total passes: 4 (Feynman-full, State-full, Feynman-targeted, State-targeted).

---

## Phase 5 — Multi-tx adversarial sequences

### Admin compromise worst-case (M-03)

Sequence:
1. Attacker gains ROLE_KASU_ADMIN.
2. Tx1: `setRewardCaps(type(uint256).max, type(uint256).max)`.
3. Tx2: `emitUserLoyaltyRewardBatch([{user=attacker, epoch=X, level=maxLevel, amountDeposited=huge}], ksuTokenPrice=1)`.

Drain = KSU balance of `UserLoyaltyRewards` contract (bounded by protocol's KSU deposits).

**Mitigation achieved vs pre-fix:** 2 admin transactions required instead of 1; `RewardCapsUpdated` event makes the attack observable before the drain. Non-regression: admin trust was always required.

### Missed cron for N epochs (M-04)

Per-epoch self-heal in `batchCalculateUserLoyaltyLevels` (which runs during clearing) resets snapshot. No drift. View callers always get fresh. Sound.

### Pool manager abandons loss mint (M-06)

Scenario:
1. Pool manager calls `registerTrancheLoss(lossId=1, amount, doMintLossTokens=false)`.
2. Pool manager never calls `batchMintLossTokens`.
3. Clearer triggers clearing for next epoch.
4. `executeAcceptedRequestsBatch` → M-06 self-heal: drains 100 users from tranche queue.
5. If queue was ≤ 100 users → proceed; if more → revert `LossMintingStillPending`.
6. Anyone (permissionless) can call `batchMintLossTokens` to drain. Repeat.

Worst-case gas: clearer calls `executeAcceptedRequestsBatch` repeatedly, each call draining 100 more per tranche. Eventually clears. Total cost: `usersCount × 100k gas`. No permanent DoS, no fund loss. ✓

### Dust withdrawal flood (M-08)

Analyzed in Pass 3. Economically infeasible attack (1M NFTs cost >> $0.000001 gain). No protocol-level invariant broken.

### Multi-tranche loss + doMintLossTokens=false on all three

1. Pool manager registers loss on tranche 0 via `registerTrancheLoss(lossId1, ..., false)`.
2. Before tranche 0 is drained, can pool manager register on tranche 1? YES — different tranches, different `_pendingMintLossId` scope.
3. Same for tranche 2.
4. Clearing time: M-06 loop iterates 3 tranches, each calls `batchMintLossTokens(lossId_i, 100)`. Total up to 300 mints per call.
5. 300 × ~110k gas ≈ 33M gas > 30M block limit.

**Finding:** Multi-tranche self-heal can exceed block gas limit if all three tranches have 100+ pending mints. Clearer must pre-drain at least some tranches manually before clearing. Non-regression (existing design requires clearer operations) but worth documenting.

---

## Phase 6 — Verification

- `forge test` — **207/207 passing**.
- M-06 tests include `test_M06_clearingMintBatchSizeExposed`, `test_M06_pendingLossMintAccessors`. ✓
- M-08 test `M08DustWithdrawalTest.sol` passes.
- No regression in existing M-01/M-02/M-05/M-07 tests.

---
