# State Inconsistency Audit — Verified Findings

Branch: `release-candidate`
Scope: `src/core/**`, `src/locking/**`, `src/token/**`, `src/shared/**`
Methodology: State Inconsistency Auditor SKILL (Phases 1–8)
Independent re-derivation (did not lean on prior nemesis output).

---

## Phase 1 — Coupled State Dependency Map

The protocol's state coupling surface was mapped from storage declarations in every production contract and cross-referenced against every mutation site. Each pair below lists the invariant, the functions that must co-update both sides, and the outcome of the audit.

| # | Coupled Pair | Invariant | Primary Mutating Functions | Verdict |
|---|---|---|---|---|
| P1 | `userActiveShares[user]` ↔ `_trancheUsers[]` / `_userArrayIndex[user]` | `userActiveShares[u] > 0 ⇔ u ∈ _trancheUsers`, and `_trancheUsers[_userArrayIndex[u]] == u` | `LendingPoolTranche.deposit`, `LendingPoolTranche.removeUserActiveShares` | ✓ CONSISTENT |
| P2 | `userActiveShares[user]` ↔ `_userActiveTrancheCount[user]` | count == number of tranches where user has non-zero shares across all pools | `LendingPoolTranche.deposit`→`addUserActiveTranche`; `LendingPoolTranche.removeUserActiveShares`→`removeUserActiveTranche` | ✓ CONSISTENT |
| P3 | `_userActiveTrancheCount[user]` ↔ `KSULocking.isFeeRecipientEnabled[user]` | first tranche enables fees, last tranche disables them | `UserManager.addUserActiveTranche/removeUserActiveTranche` → `_ksuLocking.enableFeesForUser/disableFeesForUser` | ✓ CONSISTENT |
| P4 | `_isUser[user]` ↔ `_allUsers[]` | membership ↔ presence in dynamic array | `UserManager.userRequestedDeposit`; `UserManager._removeUserFromAllUsers` | ✓ CONSISTENT |
| P5 | `_isUserPartOfLendingPool[pool][user]` ↔ `_userLendingPools[user]` | membership ↔ presence in per-user pool array | `UserManager.userRequestedDeposit`; `_removeLendingPoolFromUser` | ✓ CONSISTENT (H-01 prior fix verified: both sides are unset inside `_removeLendingPoolFromUser`, LendingPoolTranche.sol-equivalent flow) |
| P6 | `_trancheUsers[]` ↔ `_lossDetails[lossId].usersCount` (at mint time) | usersCount snapshot frozen when pending mint begins; `_trancheUsers` mutations blocked by `notPendingLossMint` | `LendingPoolTrancheLoss._registerLoss` sets snapshot; `LendingPoolTranche.deposit`/`redeem` gated by `notPendingLossMint`; `_batchMintLossTokens` clears `_pendingMintLossId` when count reached | ✓ CONSISTENT |
| P7 | `_pendingMintLossId` ↔ `_lossDetails[lossId].usersMintedCount` / `usersCount` | non-zero iff `usersMintedCount < usersCount` | `_registerLoss`; `_batchMintLossTokens` | ✓ CONSISTENT |
| P8 | `_lossDetails[lossId].totalLossShares` ↔ ERC1155 `balanceOf(user, lossId)` | totalLossShares = Σ balance across users minted | `_mintUserLossTokens` increments both | ✓ CONSISTENT |
| P9 | `_lossDetails[lossId].recoveredAmount` ↔ `userClaimedLosses[user][lossId]` | `Σ userClaimed <= recoveredAmount` via `userClaimableLoss` pro-rata | `repayLoss`, `claimRepaidLoss` | ✓ CONSISTENT |
| P10 | `ksuEpochTokenPrice` ↔ `priceUpdateEpoch` | price is stale iff `currentEpoch > priceUpdateEpoch`; readers must use `ksuEpochTokenPriceFresh()` | `_updateKsuTokenPrice` writes both atomically; `UserManager.batchCalculateUserLoyaltyLevels` self-heals via `updateKsuEpochTokenPrice`; `_loyaltyParameters` reads via `Fresh` | ✓ CONSISTENT (M-04 fix verified — see §Verified Safe Paths) |
| P11 | `userRewards[user]` ↔ `totalUnclaimedRewards` | total = Σ per-user | `_emitUserLoyaltyReward` (++ both); `claimReward` (-- both) | ✓ CONSISTENT |
| P12 | `maxRewardPerUserPerBatch` / `maxBatchTotalReward` storage slots ↔ existing Base storage layout | append-only, no collision | new slots 54/55 after `userRewards` at slot 53 | ✓ CONSISTENT (M-03 fix verified — storage layout append is safe; see §Verified Safe Paths) |
| P13 | `_accumulatedRewardsPerShare` ↔ `_rewardDebt[user]` | `rewardDebt = rKSUForFees * accPerShare / PRECISION` at last user-balance change | `_lock`, `_withdrawUserLockId`, `claimFees`, `enableFeesForUser`, `disableFeesForUser` — all run `_updateUserRewards` → mutate balance → `_updateUserRewardDebt` | ✓ CONSISTENT |
| P14 | `eligibleRKSUForFees` ↔ rKSU `_balances` ↔ `isFeeRecipientEnabled[user]` | `eligibleRKSUForFees = Σ balanceOf(u) where isFeeRecipientEnabled[u]` | `_mintRKSU`, `_burnRKSU`, `enableFeesForUser`, `disableFeesForUser` | ✓ CONSISTENT |
| P15 | `userTotalDeposits[user]` ↔ `Σ _userLocks[user][i].amount` | equal | `_lock` (+=), `_withdrawUserLockId` (-=) | ✓ CONSISTENT |
| P16 | `_userLocks[user][i].amount` ↔ `_userLocks[user][i].rKSUAmount` | `rKSUAmount = amount * rKSUMultiplier / FULL_PERCENT` (stored) | `_lock` sets; `_withdrawUserLockId` updates both based on remaining amount | ✓ CONSISTENT |
| P17 | `firstLossCapital` ↔ `balanceOf(address(this))` on LendingPool | pool-held LP tokens represent FLC | `depositFirstLossCapital`, `withdrawFirstLossCapital`, `reportLoss` (burns from self for FLC portion only) | ✓ CONSISTENT |
| P18 | `userOwedAmount` ↔ `totalSupply(LP token)` | `availableFunds = totalSupply - userOwedAmount` | `_draw` (+=), `_applyTrancheInterest` (+=), `_applyFixedRateInterests` (±), `reportLoss` (−= appliedLoss while also burning LP to match), `repayOwedFunds` (−=), `acceptWithdrawal` (burns LP, no userOwed change — withdrawal consumes available liquidity) | ✓ CONSISTENT |
| P19 | `feesOwedAmount` ↔ LP token flow | `_applyTrancheInterest` and `_applyFixedRateInterests` accrue fees; `_payFees` decrements while emitting to FeeManager | `_applyTrancheInterest`, `_applyFixedRateInterests`, `_payFees`, `payOwedFees` (which then bumps `userOwedAmount` by amount paid out-of-pocket) | ✓ CONSISTENT |
| P20 | `_trancheDepositNftDetails[id].assetAmount` ↔ `_totalEpochPendingDepositAmount[epoch]` ↔ `totalPendingDepositAmount` ↔ `_totalUserTranchePendingDepositAmount[user][tranche]` | sum per-epoch = total; sum per-user-tranche = user's pending in that tranche | `requestDeposit` (all ++), `_acceptDepositRequest` (all −=), `_returnDepositRequest` (all −=) | ✓ CONSISTENT |
| P21 | dNFT / wNFT enumeration ↔ `AcceptedRequestsExecutionEpoch.nextIndexToProcess` | nextIndex is snapshot of `totalSupply-1` taken on init; ERC721 pending supply is frozen for target epoch because the epoch is past clearing | `executeAcceptedRequestsBatch` decrements from snapshot; deposit/withdraw/cancel blocked during clearing by `notPendingClearing` | ✓ CONSISTENT |
| P22 | `ClearingData.tranchePriorityDepositsAmounts` ↔ `ClearingData.tranchePriorityDepositsAccepted` | accepted <= deposited per (tranche, priority); verified in `_verifyResult` | `AcceptedRequestsCalculation.calculateAcceptedRequests` | ✓ CONSISTENT |
| P23 | Lock-side `deposit.trancheShares` ↔ `ILendingPoolTranche(tranche).balanceOf(FixedTermDeposit)` | FTD's ERC20 balance per tranche == Σ deposit.trancheShares for active deposits in that tranche | `_lockFixTermDeposit` (transfer in), `_endFixedTermDeposit` (transfer out), `applyFixedTermInterests` (mint/burn diff and updates deposit.trancheShares — FixedTermDeposit.sol:489-494, fix for userTrancheSharesAfter) | ✓ CONSISTENT (prior bug fix verified) |
| P24 | `deposit.withdrawRequested` ↔ pending withdrawal wNFT existence | a priority withdrawal is filed for user iff withdrawRequested==true and unlock epoch reached | `requestFixedTermDepositWithdrawal`, `cancelFixedTermDepositWithdrawalRequest`, `applyFixedTermInterests` (lines 503-508 — requests priority withdrawal only if `withdrawRequested && userTrancheSharesAfter > 0`) | ✓ CONSISTENT |
| P25 | `_lendingPoolFixedTermDepositIds[pool][]` ↔ `_lendingPoolFixedTermDepositIdToLock[pool][id]` | id ∈ array ⇔ lock entry non-empty | `_lockFixTermDeposit` (push + set), `_endFixedTermDeposit` (swap-pop + delete) | ✓ CONSISTENT |
| P26 | `_epochUserLoyaltyProcessing[e].userCount` ↔ `_allUsers.length` at start-of-epoch | userCount captured once on first call to `batchCalculateUserLoyaltyLevels` for epoch; `updateUserLendingPools` blocked during clearing time | `batchCalculateUserLoyaltyLevels` (init once); `updateUserLendingPools` (guarded by `!isClearingTime`) | ✓ CONSISTENT |
| P27 | `_userEpochLoyaltyLevel[user][epoch]` ↔ `_epochUserLoyaltyProcessing[epoch].processedUsersCount` | level written for `_allUsers[0..processedUsersCount)` for this epoch | `batchCalculateUserLoyaltyLevels` | ✓ CONSISTENT |
| P28 | ERC4626 `totalAssets` / `totalSupply` ↔ `userActiveShares[]` | Σ userActiveShares == ERC4626 totalSupply (because all minting goes through deposit() which also ++userActiveShares, and all burning goes through redeem()+removeUserActiveShares()) | `deposit`, `redeem`+`removeUserActiveShares` | ✓ CONSISTENT |
| P29 | Self-heal loss mint in `executeAcceptedRequestsBatch` ↔ `_pendingMintLossId` | if partial, revert with `LossMintingStillPending`; if full, proceeds and is observed as `!isPendingLossMint` | loop per tranche at AcceptedRequestsExecution.sol:92-101 | ✓ CONSISTENT (M-06 fix verified — partial mint NEVER leaves clearing mid-flight; either drains fully or reverts atomically before touching any tranche shares) |

**Total coupled pairs mapped: 29.**

---

## Phase 2 — Mutation Matrix

The full mutation matrix was built and audited (each row traced against each coupled pair). No GAP cells emerged for any coupled pair. Key high-risk matrix rows worth calling out explicitly:

| State | Mutating sites | Coupled state verified updated at every site |
|---|---|---|
| `userActiveShares[user]` | `LendingPoolTranche.deposit`, `removeUserActiveShares` | `_trancheUsers[]`, `_userArrayIndex[user]`, `_userActiveTrancheCount[user]` |
| `_pendingMintLossId` | `_registerLoss` (set), `_batchMintLossTokens` (clear on complete) | `_lossDetails[id].usersMintedCount/usersCount`; guarded by `notPendingLossMint` on deposit/redeem |
| `userOwedAmount` | `_draw`, `_applyTrancheInterest`, `_applyFixedRateInterests` (both branches), `reportLoss`, `repayOwedFunds`, `payOwedFees` | Each site matches a corresponding LP-token mint/burn or asset flow that preserves `availableFunds = totalSupply - userOwedAmount` |
| `firstLossCapital` | `depositFirstLossCapital`, `withdrawFirstLossCapital`, `reportLoss` | Each site pairs with `_mint/_burn(address(this), ...)` so that pool's LP-token self-balance tracks FLC |
| `eligibleRKSUForFees` | `_mintRKSU`, `_burnRKSU`, `enableFeesForUser`, `disableFeesForUser` | All mint/burn paths of rKSU pass through `_mintRKSU/_burnRKSU`; rKSU has no transfer path |
| `_rewardDebt[user]` | `_lock`, `_withdrawUserLockId`, `enableFeesForUser`, `claimFees`, `disableFeesForUser` | Every balance-change site is sandwiched by `_updateUserRewards` → mutation → `_updateUserRewardDebt` |

---

## Phase 3–7 Findings

### Phase 3 (coupled-state gap sweep)
No gaps found.

### Phase 4 (intra-function ordering)
Verified the MasterChef-style sequence in all KSULocking balance mutators (`_lock`, `_withdrawUserLockId`, `enableFeesForUser`, `disableFeesForUser`). Verified the epoch-price self-heal ordering in `batchCalculateUserLoyaltyLevels` (heal first, then snapshot `params`, then loop).

### Phase 5 (parallel path comparison)

| Coupled State | `acceptDeposit`/`deposit` | `acceptWithdrawal`/`redeem`+`removeUserActiveShares` | `forceImmediateWithdrawal` | FTD unlock `_endFixedTermDeposit` | `_applyFixedRateInterests` |
|---|---|---|---|---|---|
| `userActiveShares` | ✓ ++  | ✓ −− (via `removeUserActiveShares`) | ✓ −− (calls `removeUserActiveShares` explicitly — LendingPool.sol:674) | ✓ untouched (FTD transfer only) | ✓ ± via deposit() / `removeUserActiveShares` |
| `_trancheUsers[]` | ✓ push if 0→nonzero | ✓ pop if →0 | ✓ pop if →0 | ✓ untouched | ✓ via the two paths above |
| `_userActiveTrancheCount` | ✓ `addUserActiveTranche` on 0→nonzero | ✓ `removeUserActiveTranche` on →0 | ✓ same | ✓ untouched | ✓ same |
| `firstLossCapital` | N/A | N/A | N/A | N/A | N/A (doesn't touch FLC) |
| ERC20 LP `totalSupply` | ✓ mint | ✓ burn | ✓ burn | N/A (tranche share transfer only) | ✓ mint (positive) / burn (negative) |
| `userOwedAmount` | N/A | N/A | N/A | N/A | ✓ ± in both branches matches LP mint/burn |

All parallel paths update the same coupled state.

### Phase 6 (multi-tx / multi-user)
Traced these sequences — all clean:
1. User A deposits → partial withdraw → claim loss → fully withdraw.  Verified `userClaimableLoss` remains deterministic because `totalLossShares` and `balanceOf(A, lossId)` are frozen after the mint batch, and `recoveredAmount` is monotone.
2. User locks KSU → fees emitted → re-lock more KSU (ensures earned carries over correctly via `_updateUserRewards` then `_updateUserRewardDebt`).
3. User deposits FTD in tranche T → base rate drops below fixed rate → `_applyFixedRateInterests` mints extra shares to user and transfers to FTD → user withdraws FTD on unlock. `deposit.trancheShares` carries the post-interest figure (bug fix at FixedTermDeposit.sol:469 `userTrancheSharesAfter = trancheShares` — previously defaulted to 0 in the no-diff branch, now correctly defaults to incoming `trancheShares`, so `deposit.trancheShares` isn't zeroed when `balanceBefore == balanceAfter`).
4. Loss reported with `doMintLossTokens=false`, many users, half-minted by a random caller, then clearing triggers → `AcceptedRequestsExecution` drains up to 100 users; if still pending, reverts with `LossMintingStillPending` BEFORE touching any tranche share. Atomic. No inconsistent mid-clearing state.

### Phase 7 (masking-code review)
- `ksuEpochTokenPriceFresh()` — falls back to spot when stale. This is NOT masking: it's defense-in-depth for view callers; the mutative path (`batchCalculateUserLoyaltyLevels`) self-heals first so the snapshot is guaranteed fresh when shares are accrued.
- Dust clamp in `AcceptedRequestsExecution.sol:207-209` (`if (acceptedWithdrawalShares == 0 && sharesAmount > 0) acceptedWithdrawalShares = sharesAmount;`) — intentional fairness fallback (M-08). This DOES change economic distribution — small withdrawal requests that would truncate to zero now get fully accepted — but **does not break any coupled-state invariant**: the full `sharesAmount` is available in PendingPool's tranche balance (it was transferred in on `requestWithdrawal`), `userActiveShares[user]` is decremented to match, `_trancheUsers[]` / `_userActiveTrancheCount` update as normal via `removeUserActiveShares`, and `totalSupply` burn matches assets out. The observed side-effect is a small over-distribution of assets relative to the clearer-calculated `totalAcceptedAmount`, which is a FAIRNESS/accounting question between dust and non-dust participants inside a partially-accepted priority bucket, not a state desync. Flagged here for completeness; no state-consistency finding.
- `endFixedTermDeposit` fallback-loop in FixedTermDeposit.sol:352-358: if `arrayIndex` doesn't match, scans linearly. Defensive but not masking — both the array and the id-to-lock map are deleted atomically in `_endFixedTermDeposit`, and the linear scan finds the canonical index.

---

## Phase 8 — Verification Summary

| ID | Coupled Pair | Breaking Op | Pre-Verification | Verdict | Final |
|---|---|---|---|---|---|
| candidate-1 | P29 (loss self-heal) | `executeAcceptedRequestsBatch` drains 100 users, then reverts atomically if more remain | MEDIUM | FALSE POSITIVE | NONE |
| candidate-2 | M-08 dust fallback vs `sum(acceptedShares) <= totalAccepted` invariant | `_acceptWithdrawalRequest` dust branch | MEDIUM | FALSE POSITIVE (not a state desync; coupled-pair invariants hold) | NONE |
| candidate-3 | P10 `ksuEpochTokenPrice` stale reads | view-caller reading `ksuEpochTokenPrice` direct | LOW | FALSE POSITIVE (`ksuEpochTokenPriceFresh()` is the only sanctioned read path and is used everywhere) | NONE |
| candidate-4 | P5 `_isUserPartOfLendingPool` H-01 re-verification | `_removeLendingPoolFromUser` | HIGH-if-broken | TRUE NEGATIVE (fix is correct: both sides cleared — UserManager.sol:506) | NONE |
| candidate-5 | P12 storage layout | `maxRewardPerUserPerBatch` / `maxBatchTotalReward` | HIGH-if-broken | TRUE NEGATIVE (append-only after slot 53) | NONE |

**All C/H/M candidates verified as false positives (none expose a real desync).**

---

## Verified Findings

**NONE at CRITICAL, HIGH, MEDIUM, or LOW severity.**

Every coupled pair in the dependency map synchronizes correctly across every mutation path. The four prior-fix sites (M-03, M-04, M-06, M-08) were re-examined against first-principles couplings and all four hold up.

---

## False Positives Eliminated (with reasoning)

1. **M-08 dust fallback as alleged over-issuance desync.** Re-traced: the extra shares accepted above the pro-rata calculation come from PendingPool's own tranche balance (sourced from `requestWithdrawal`'s `safeTransferFrom(user, pp)`). PendingPool always holds `>= Σ user sharesAmount` per priority, so the dust fallback cannot underflow pp's balance. `userActiveShares[user]` is decremented by exactly the accepted amount inside `removeUserActiveShares`, so `_trancheUsers[]` / `_userActiveTrancheCount` stay in lockstep. `totalSupply` of LP tokens drops by the asset amount burned, matching the USDC transferred out. The only side-effect is that, inside a partially-accepted priority bucket, dust NFTs get a better effective ratio than non-dust NFTs — an intra-priority fairness effect, not a coupled-state break. Not a state inconsistency finding.

2. **Self-heal loss-mint draining as possible mid-clearing partial state.** The self-heal (AcceptedRequestsExecution.sol:92-101) runs BEFORE any tranche share mutation in the batch. If the 100-user drain doesn't complete the loss mint, the transaction reverts atomically — no deposit / redeem has happened yet, no `userActiveShares` mutated. The next call re-enters this same guard. State is only observed fully-minted or fully-pre-clearing.

3. **`ksuEpochTokenPrice` self-heal via `batchCalculateUserLoyaltyLevels`.** The mutative path explicitly calls `_systemVariables.updateKsuEpochTokenPrice()` (UserManager.sol:257) as the FIRST side-effect of the clearing-time batch. This guarantees `priceUpdateEpoch == currentEpoch` before any reward is computed. `_loyaltyParameters` reads the fresh value via `ksuEpochTokenPriceFresh()`, which additionally falls back to spot for view callers. Two layers of defense; no read site I found bypasses both.

4. **FTD `userTrancheSharesAfter` default.** The fix at FixedTermDeposit.sol:469 (`uint256 userTrancheSharesAfter = trancheShares;`) correctly initializes the post-interest figure to the pre-interest figure, preserving `deposit.trancheShares` when base-rate-diff == 0. Verified via Phase 6 multi-tx trace; no zeroing on no-op epochs.

---

## Summary

- **Coupled state pairs mapped:** 29
- **Mutation paths analyzed:** every write site for each pair
- **Raw findings (pre-verification):** 5 candidates
- **After verification:** 0 TRUE POSITIVE | 5 FALSE POSITIVE
- **Final:** 0 CRITICAL | 0 HIGH | 0 MEDIUM | 0 LOW

**Verdict: the `release-candidate` branch is state-consistency-clean.** Every coupled pair reconciles on every mutation path; every parallel path handles the same coupled state; every masking-pattern candidate was traced to an intentional, invariant-preserving design choice (dust fairness, view-layer price fallback, atomic loss-mint drain). The prior round of fixes (M-03 / M-04 / M-06 / M-08) does not introduce new state desyncs and does not break existing couplings. Ready to ship from a state-inconsistency perspective.
