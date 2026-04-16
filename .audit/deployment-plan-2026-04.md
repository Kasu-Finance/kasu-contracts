# Deployment Upgrade Plan — April 2026 Security Fixes

**Commit:** `f8d2d45` on `release-candidate`
**Fixes covered:** M-03, M-04, M-06, M-08, FV-01 (April 2026 audit + post-fix Feynman re-audit)
**Target chains, in order:** XDC USDC → XDC AUDD → Plume → Base
**Rollout strategy:** smallest blast-radius first, proven working before moving up the stack.

## Contracts changed in this commit

| Contract | Type | Chains affected | Storage change |
|---|---|---|---|
| `SystemVariables.sol` | Transparent proxy | All 4 | No (added view only) |
| `UserManager.sol` | Transparent proxy | Base only (Lite overrides to no-op) | No |
| `UserManagerLite.sol` | Transparent proxy | 3 Lite chains | No (inherits) |
| `UserLoyaltyRewards.sol` | Transparent proxy | Base only | **Yes — 2 new slots appended** |
| `UserLoyaltyRewardsLite.sol` | Transparent proxy | 3 Lite chains | No |
| `LendingPoolTrancheLoss.sol` | Beacon (via tranche) | All 4 | No (views added) |
| `AcceptedRequestsExecution.sol` | Beacon (via PendingPool) | All 4 | **Yes — struct extended with mapping** |

### Source-verification drift from forge fmt

The `ci(fmt)` commit reformatted 5 files in `src/core/clearing/**` to align with CI's pinned forge v1.5.1. Pure whitespace changes — runtime bytecode is byte-identical (modulo the metadata hash suffix which Etherscan strips before compare).

**However**, `validateDeployment.ts` compares the Etherscan-verified source against the local source with only CRLF normalization — pure whitespace diffs will show as `'mismatch'` until re-verification lands.

Two contracts are independently deployed and will flag on all 4 chains:
- `AcceptedRequestsCalculation` (own proxy address)
- `ClearingCoordinator` (own proxy address)

**Resolution:** just re-verify them on the explorer with the new source. No gas cost, no redeployment. The one-liner `AUTO_VERIFY=true ETHERSCAN_API_KEY=... npx hardhat --network <net> run scripts/admin/validateDeployment.ts` will do this automatically and clear the flag. Add this step to each chain's rollout.

The other 3 fmt'd files (`AcceptedRequestsExecution`, `ClearingSteps`, `PendingRequestsPriorityCalculation`) are abstract / inherited by `PendingPool`. They roll into the new `PendingPool` impl deployed for M-06/FV-01 and get verified together with it — no extra step needed.

### Storage layout verdict

Both state changes are additive and upgrade-safe:
- `UserLoyaltyRewards`: two `uint256` slots (`maxRewardPerUserPerBatch`, `maxBatchTotalReward`) appended after existing `userRewards` mapping.
- `AcceptedRequestsExecution`: new mapping field added to the existing `AcceptedRequestsExecutionEpoch` struct that lives inside an outer mapping. Mapping-in-struct extensions don't shift any contract's storage slots (each entry is at its own `keccak256(key . slot)` base).

**⚠️ Hardhat-upgrades plugin caveat:** the OZ hardhat-upgrades plugin runs a conservative static layout check and WILL flag the struct extension even though it's runtime-safe. Workaround at upgrade time:

```ts
// In the upgrade script, when calling upgrades.upgradeProxy on PendingPool:
await upgrades.upgradeProxy(pendingPoolProxy, PendingPoolFactory, {
    unsafeAllow: ['struct-definition'],
    // alternatively, validate manually and use unsafeSkipStorageCheck: true on this one contract
});
```

Verify manually by reading the EIP-1967 impl slot before and after to confirm the upgrade landed, and by running the full smoke-test suite after.

## Per-chain upgrade packages

Each chain needs these proxy upgrades:

| Proxy | Implementation contract | Chain scope |
|---|---|---|
| SystemVariables proxy | `SystemVariables` | All 4 |
| UserManager proxy | `UserManager` (Base) / `UserManagerLite` (3 Lite) | All 4 |
| UserLoyaltyRewards proxy | `UserLoyaltyRewards` (Base) / `UserLoyaltyRewardsLite` (3 Lite) | All 4 |
| **PendingPool beacon** | `PendingPool` | All 4 |
| **LendingPoolTranche beacon** | `LendingPoolTranche` | All 4 |

**5 proxy/beacon upgrades per chain × 4 chains = 20 upgrade txs total**, executed as 4 Gnosis Safe batch transactions (one per chain).

---

## Chain 1 — XDC USDC (Lite) — FIRST

**Why first:** smallest TVL, newest deployment, no active pool operations yet (Apxium hasn't created pools). Low blast radius validates the upgrade procedure before touching more mature chains.

**Rollout steps:**

1. **Anvil fork dry-run**
   ```bash
   anvil --fork-url https://rpc.xdc.org --chain-id 50 --port 8546
   # Point hardhat at the fork, simulate all 5 upgrades via scripted deploy of new impls + upgradeAndCall through ProxyAdmin
   ```
2. **Deploy new implementations** (deployer tx, no multisig — impls are just stateless bytecode)
   - Reuse/adapt `scripts/upgrade/upgradeXdcImplementations.ts` pattern — create `scripts/upgrade/deployXdcUsdcImplementations.ts` that outputs a Safe tx batch JSON
   - Outputs: 5 new impl addresses + `scripts/multisig/xdc-usdc-upgrade-2026-04.json`
3. **Upgrade ProxyAdmins via Kasu Multisig** (`0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`)
   - Upload the Safe batch JSON to XDC Safe (https://app.safe.global on chain 50)
   - 5 `upgradeAndCall(proxy, newImpl, 0x)` txs against each proxy's dedicated ProxyAdmin
   - Beacon upgrades: 2 `upgradeTo(newImpl)` calls on PendingPoolBeacon + LendingPoolTrancheBeacon
4. **Verify on xdcscan**
   ```bash
   AUTO_VERIFY=true ETHERSCAN_API_KEY=... npx hardhat --network xdc-usdc run scripts/admin/validateDeployment.ts
   ```
5. **Smoke tests**
   ```bash
   npx hardhat --network xdc-usdc run scripts/smokeTests/validateDeploymentComplete.ts
   # Expect: 25/25 global checks passing, 0 pools (none created yet)
   ```
6. **No post-upgrade admin calls needed on Lite** — reward caps are Base-only (Lite has `UserLoyaltyRewardsLite` which no-ops the batch emission function).

**Success criteria:** all smoke tests green, 0 source mismatches.

---

## Chain 2 — XDC AUDD (Lite)

**Why second:** same chain as XDC USDC (reuses same multisig), validated upgrade procedure from chain 1, 3 active pools with live deposits.

**Pre-upgrade considerations:**
- 3 pools have active deposits. Run upgrades **outside the clearing window** (Tuesday 06:00 → Thursday 06:00 UTC) to avoid clashing with ongoing clearing.
- Pools: check `scripts/_config/chains.ts` `xdc` entry for addresses.

**Rollout:** same 6 steps as XDC USDC. Use `scripts/multisig/xdc-audd-upgrade-2026-04.json`.

**Post-upgrade validation:**
```bash
npx hardhat --network xdc run scripts/smokeTests/validateDeploymentComplete.ts
# Expect: 25 global + 12 pool checks passing (3 pools × 4 role checks)
```

**Sanity check after upgrade:** do a withdrawal test on one pool if possible — exercise the new FV-01 budget tracking code path in production conditions without real funds at risk (use a known test address with dust-sized position).

---

## Chain 3 — Plume (Lite)

**Why third:** 3 active pools, single chain, proven Lite upgrade flow from XDC.

**Special considerations:**
- Uses Blockscout, not Etherscan V2. No API key needed but verification UX is different.
- ProxyAdmin owner: `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`

**Rollout:** same 6 steps. Use `scripts/multisig/plume-upgrade-2026-04.json`.

**Verify via Blockscout** (not Etherscan):
```bash
npx hardhat --network plume run scripts/admin/validateDeployment.ts
# Uses Blockscout API automatically
```

---

## Chain 4 — Base (Full) — LAST AND MOST CRITICAL

**Why last:** largest TVL, Full deployment (KSU token + loyalty rewards + locking live), active weekly loyalty emission via cron.

### Additional complexity vs Lite chains

1. **UserLoyaltyRewards has new storage** — 2 slots appended. Storage layout is safe but must be verified on deployed state.
2. **`setRewardCaps(perUser, perBatch)` MUST be called after upgrade, in the SAME Safe batch, before the next weekly loyalty batch emission.** Otherwise the backend's weekly emission tx reverts with `RewardCapsNotSet`.

### Choosing cap values

**Units:** both caps are in **KSU tokens at 18-decimal precision (wei)**, NOT USDC. `emitUserLoyaltyRewardBatch` compares them against `ksuReward` computed from `(amountDeposited * epochRewardRate * KSU_PRICE_MULTIPLIER * 1e12) / ksuTokenPrice / INTEREST_RATE_FULL_PERCENT`, which yields KSU amounts.

Example: a 1,000 KSU cap is `1_000 * 1e18` passed to `setRewardCaps`.

**Initial cap (pre-token-launch):** the KSU token doesn't exist yet, so there's no historical emission data to calibrate against. Use a conservative blanket cap of **1,000 KSU per epoch** until real emission volume is observed:

```solidity
// Initial values for the first upgrade on Base
setRewardCaps(1_000 * 1e18, 1_000 * 1e18);
//            ↑ perUser     ↑ perBatch
// Both set to 1_000 KSU wei. Batch cap bounds total epoch emission at 1,000 KSU,
// per-user cap equals batch cap so a single dominant user isn't artificially
// throttled below the overall budget.
```

**Post-launch retune:** once KSU is live and weekly emission volume stabilizes, call `setRewardCaps` again with values calibrated from historical `UserLoyaltyRewardsEmitted(user, epoch, rewardAmount)` events (rewardAmount is the KSU wei amount):

- `maxRewardPerUserPerBatch`: 2× largest observed per-user reward in last 10 weekly batches
- `maxBatchTotalReward`: 1.5× largest observed total-batch reward in last 10 weekly batches

Caps are settable by `ROLE_KASU_ADMIN` at any time — no upgrade needed for retunes.

### Rollout steps

1. **Anvil fork dry-run on Base** — run the full upgrade + `setRewardCaps` + a simulated `emitUserLoyaltyRewardBatch` to confirm the flow works end to end.
2. **Deploy implementations** via deployer tx.
3. **Gnosis Safe batch** via Kasu Multisig (`0xC3128d734563E0d034d3ea177129657408C09D35`):
   - Tx 1–3: upgrade SystemVariables, UserManager, UserLoyaltyRewards transparent proxies
   - Tx 4: beacon upgrade PendingPool
   - Tx 5: beacon upgrade LendingPoolTranche
   - **Tx 6: call `UserLoyaltyRewards.setRewardCaps(perUser, perBatch)`** — mandatory, see cap values section
4. **Verify on Etherscan V2**
   ```bash
   AUTO_VERIFY=true ETHERSCAN_API_KEY=... npx hardhat --network base run scripts/admin/validateDeployment.ts
   ```
5. **Smoke tests**
   ```bash
   npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
   # Expect: 25 global + N pool checks + Tenderly simulation
   ```
6. **Tenderly createPool simulation** runs automatically as part of smoke tests on Base. Extend the simulation suite with a `setRewardCaps` + `emitUserLoyaltyRewardBatch` tenderly sim to validate caps don't block legitimate emissions.
7. **Live-fire test (low stakes):** ask the backend to emit a minimal test batch (e.g., one user, $0.01 reward) within the first 24h after upgrade to confirm caps don't accidentally revert the real batch.

### Rollback plan for Base

If the upgrade breaks something critical:
- Each proxy upgrade is reversible — the old impl addresses are recorded in `.openzeppelin/base.json`. A single Safe tx per proxy downgrades back.
- Beacon upgrades are equally reversible.
- `setRewardCaps` — can be set to `(type(uint256).max, type(uint256).max)` to effectively disable the cap check without removing it, if cap values turn out to be miscalibrated.

---

## Execution checklist — to-do before each chain

- [ ] Run `forge test` one final time — confirm 208/208 passing against the exact HEAD being deployed
- [ ] Anvil fork dry-run of all 5 proxy upgrades + post-upgrade calls
- [ ] Check no active clearing window on target chain (Tuesday 06:00 → Thursday 06:00 UTC)
- [ ] Generate Safe batch JSON + commit to `scripts/multisig/`
- [ ] Circulate Safe batch for multisig signers ≥24h before execution
- [ ] Pre-write smoke test expected output (e.g. "25 global + 12 pool checks passing")
- [ ] Pre-write validateDeployment expected output ("0 source mismatches")
- [ ] Block out deployer time for live monitoring during and 24h after execution

## Post-execution checklist — after all 4 chains

- [ ] All `.openzeppelin/*-addresses.json` files updated with new implementation addresses
- [ ] All 4 chains show 0 source mismatches via `validateDeployment.ts`
- [ ] All 4 chains verified on their respective explorers
- [ ] Smoke tests pass on all 4 chains
- [ ] Backend confirms loyalty emission works on Base with the new caps
- [ ] Update `CLAUDE.md` with "April 2026 security upgrade complete" entries per chain
- [ ] Tag `release-candidate` at `f8d2d45` (or post-merge commit on main)
- [ ] Publish the April 2026 v3 audit report (with all 10 findings marked RESOLVED)
