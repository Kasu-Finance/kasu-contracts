## ⚠️ 🚧 TODO — stuff that isn't on-chain yet

Heads up before you wire anything up: the pools aren't live yet, so a bunch of values below are placeholders. Don't hard-code any of them — we'll fill them in once Apxium creates the pools and configs.

- 🚧 **Pool addresses (3 USDC pools)** — §1. Not created yet, Apxium's job.
- 🚧 **Tranche addresses per pool** — §1. Read from `lendingPoolInfo()` once the pools exist.
- 🚧 **`PendingPool` address per pool** — §1. Same, from `lendingPoolInfo()`.
- 🚧 **`fixedTermConfigId` per pool** — §2. Should end up as `1` (first config on each pool) but don't bet on it — read `lendingPoolFixedTermDepositConfigCount(pool)` at startup and verify.
- 🚧 **Lock duration per pool** — §2. 26w or 52w, TBD per pool.
- 🚧 **Interest rate per pool** — §2. TBD per pool.
- 🚧 **Exact `xdc-usdc` epoch anchor** — §5. Same slot as XDC AUDD (Thu 06:00 UTC), but read `epochStartTimestamp` to confirm rather than trusting this sentence.

We'll update this doc as values land on-chain. In the meantime, your integration should read and verify everything at startup — see §4 "Reading FT config".

---

## 1. Smart Contract Access

### Contract addresses (XDC mainnet, chainId 50, `xdc-usdc` deployment)
/sim
Entry point and core:

| Contract              | Address                                      |
| --------------------- | -------------------------------------------- |
| `LendingPoolManager`  | `0x5ba223175F61221fbc795F71a41f52Bff825C68b` |
| `SystemVariables`     | `0xb73Ebe67c8597d55A5F4FCc2C1638eDd5512BfBb` |
| `KasuAllowList`       | `0xaf911547FD38686a88fc26B2A722F870426bCD6D` |
| `ClearingCoordinator` | `0x84022117eAD4C22D8A01bC7Fc9743dd101C6a882` |
| `FixedTermDeposit`    | `0x3f0685e6B1aD224D9b780Ff5E7230Ff021EfF9f0` |
| `KasuController`      | `0xe76eE99fC85531857B9011C1D4223C7D1B591D60` |
| `FeeManager`          | `0x10Ed8d3668826293935Ab5C7d4Df86cdc2D124B3` |
| `LendingPoolFactory`  | `0x8bFe5508B61b46ACB1c141eB4C04e11515F5A618` |

**🚧 TODO — the 3 USDC pools aren't live yet.** Apxium's pool admin multisig will create them shortly. Once they do, we'll drop pool / tranche / `PendingPool` addresses and FT config IDs straight into the table below.

| Pool            | Address           | Tranches (shares vault holds) | PendingPool     | `fixedTermConfigId` | Lock duration | Rate (per epoch) |
| --------------- | ----------------- | ----------------------------- | --------------- | ------------------- | ------------- | ---------------- |
| POOL_A          | 🚧 TODO           | 🚧 TODO                       | 🚧 TODO         | 🚧 TODO (expected 1) | 🚧 TODO       | 🚧 TODO          |
| POOL_B          | 🚧 TODO           | 🚧 TODO                       | 🚧 TODO         | 🚧 TODO (expected 1) | 🚧 TODO       | 🚧 TODO          |
| POOL_C          | 🚧 TODO           | 🚧 TODO                       | 🚧 TODO         | 🚧 TODO (expected 1) | 🚧 TODO       | 🚧 TODO          |

Each pool, once created, exposes its `PendingPool` and `tranche[]` addresses via:

```solidity
LendingPoolInfo memory info = ILendingPool(pool).lendingPoolInfo();
// info.trancheAddresses    -> address[]
// info.pendingPool         -> address
```

### Contract ABIs

ABIs published with the SDK: <https://github.com/Kasu-Finance/kasu-sdk/tree/main/abis>

### Admin wallets

- Pool rate updates and FT config changes: **Apxium Pool Manager Multisig** (`ROLE_POOL_MANAGER`) `0x21567eA21b14BEd14657e9725C2FE11C7be942B1`
- Pool creation: **Apxium Pool Admin Multisig** (`ROLE_LENDING_POOL_CREATOR`) `0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112`
- Allowlist additions and protocol-level admin: **Kasu Multisig** (`ROLE_KASU_ADMIN`) `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`

---

## 2. Integration model — what is pre-configured for Raze before launch

For each of the three USDC pools, Apxium will configure a single FixedTermDeposit config:

| Setting                       | Value                                                                       |
| ----------------------------- | --------------------------------------------------------------------------- |
| `fixedTermConfigId` per pool  | 🚧 **TODO** — expected `1` (each pool's first config); **verify on-chain**  |
| Lock duration                 | 🚧 **TODO** — 26 or 52 epochs (≈ 6 or 12 months), per pool                  |
| Interest rate (per epoch)     | 🚧 **TODO** — per pool                                                      |
| Status                        | `WHITELISTED_ONLY` with the Raze vault address whitelisted on each config   |
| Withdrawal request window     | `requestEpochsInAdvance = 1`, `cancelRequestEpochsInAdvance = 0` (shortest possible — see §6) |

Kasu will also add the Raze vault to the global `KasuAllowList`.

The Raze vault is the only on-chain depositor; **end users are invisible to Kasu**. The vault is responsible for end-user accounting, end-user KYC, and any internal share/IOU model.

---

## 3. Deposit flow

### Function

```solidity
// Step 1: approve USDC spend on LendingPoolManager
IERC20(USDC).approve(LendingPoolManager, amount);

// Step 2: request deposit (queued; receipt = ERC721 dNFT minted to the vault on the same tx)
uint256 dNftId = ILendingPoolManager(LendingPoolManager).requestDeposit(
    address lendingPool,        // POOL_A | POOL_B | POOL_C (TBD)
    address tranche,            // from ILendingPool(pool).lendingPoolInfo().trancheAddresses
    uint256 maxAmount,          // USDC amount (6 decimals)
    bytes(""),                  // swapData — empty (USDC is the pool asset, no swap)
    uint256 fixedTermConfigId,  // 1 — the FT config whitelisted to the vault
    bytes("")                   // depositData — empty or custom tracking data
);
```

> ⚠️ **Pass the FT `configId` you read on-chain (we expect `1`), never `0`.** `0` means "flexible path" — the vault isn't whitelisted there and the tx will revert with `UserNotInAllowList(vault)` (flexible deposits require per-user KYC, which doesn't apply to a vault-as-depositor model).

### Reading the FT config (do this at startup, and after admin events)

Before the first deposit, and any time you see a config-related admin event fire, read the FT config and bail out if anything's off. This avoids silently depositing into a config that's been disabled, re-scoped to a different tranche, or had the vault removed from the whitelist.

```solidity
// Full config struct:
FixedTermDepositConfig memory cfg =
    IFixedTermDeposit(FixedTermDeposit).lendingPoolFixedTermConfig(pool, configId);
// cfg.tranche                 -> must equal the tranche you're about to deposit into
// cfg.epochLockDuration       -> lock length in epochs
// cfg.epochInterestRate       -> per-epoch rate (18 decimals, 1e18 = 100%)
// cfg.fixedTermDepositStatus  -> WHITELISTED_ONLY (1) is the one you want. DISABLED (2) → stop.

// Is the vault still on the per-config allowlist?
bool allowed = IFixedTermDeposit(FixedTermDeposit)
    .fixedTermDepositsAllowlist(pool, configId, vaultAddress);
require(allowed, "vault no longer whitelisted on this FT config");

// While the configId itself is TBD, count how many configs exist so you can confirm "1" is correct:
uint256 count = IFixedTermDeposit(FixedTermDeposit).lendingPoolFixedTermDepositConfigCount(pool);

// Withdrawal window (you'll need this in §6):
LendingPoolWithdrawalConfiguration memory w =
    IFixedTermDeposit(FixedTermDeposit).lendingPoolWithdrawalConfiguration(pool);
// w.requestEpochsInAdvance, w.cancelRequestEpochsInAdvance
```

### Partial fills at clearing (deposits)

If a tranche is capacity-constrained at clearing, a dNFT can be **partially filled** — `acceptedAmount` in the event is less than what you requested. The leftover stays on the same dNFT and is automatically re-queued for the next epoch. The dNFT is only burned when it's fully filled or cancelled.

- Watch `DepositRequestAccepted(user, tranche, dNftId, acceptedAmount, trancheSharesMinted)` and compare `acceptedAmount` against the amount you originally sent in.
- `DepositRequestRejected` only fires if the request can't be filled at all (e.g. tranche config rejects it outright). Rejections refund USDC back to the vault.
- Heads up for accounting: if you've already told your end users "your X USDC is in pool Y," a partial fill means their principal lands across two (or more) epochs with different FT unlock dates. The same `(tranche, fixedTermConfigId, requestEpochId)` merge rule from §3 applies to the carried-over remainder, so a partial-fill remainder + a fresh same-epoch deposit still collapse into one dNFT.

### Cancelling a pending deposit

Any time before the epoch's clearing window opens, the dNFT owner (= the vault) can cancel:

```solidity
ILendingPoolManager(LendingPoolManager).cancelDepositRequest(lendingPool, dNftId);
// Reverts with CannotCancelRequestIfClearingIsPending() if clearing has already started.
// On success: USDC refunded to the vault, dNFT burned.
```

Note: `cancelRequestEpochsInAdvance = 0` on the FT withdrawal config only affects withdrawal cancellations, not these deposit cancellations.

### Receipts the vault contract must handle

The vault contract must implement:

- `IERC721Receiver` — Kasu mints **dNFTs** (deposit receipts) and **wNFTs** (withdrawal receipts) to the depositor.
- `IERC1155Receiver` — Kasu mints loss-tokens via ERC1155 if a tranche realises a loss event. Required even if no losses occur.

### ⚠️ Same-epoch dNFT merge (read this twice)

Kasu's `PendingPool` keys deposit NFTs by `(user, requestEpochId, tranche, fixedTermConfigId)`. Two `requestDeposit` calls from the same vault into the same `(tranche, fixedTermConfigId)` **within the same Kasu epoch** do not produce two NFTs — the second call **merges into the first** (`assetAmount += amount`, [`PendingPool.sol:268`](../src/core/lendingPool/PendingPool.sol#L268)).

Consequence at clearing: **one merged dNFT → one FixedTermDeposit lock with combined principal and one unlock date**. Kasu has no view of which of the vault's end users contributed which fraction.

| Scenario                                                                | dNFTs produced | FT locks at clearing                                              |
| ----------------------------------------------------------------------- | -------------- | ----------------------------------------------------------------- |
| End users A and B both deposit Mon (same epoch, same pool)              | 1              | 1 merged lock; vault must split principal + yield off-chain       |
| End user A deposits Mon, end user B deposits next Mon (different epoch) | 2              | 2 separate locks, 2 separate unlock dates                         |
| End user A deposits Mon then again Wed (same epoch)                     | 1              | 1 merged lock; vault must internally track two contributions      |

**Vault implementation requirement:** for each Kasu `fixedTermDepositId`, maintain a per-end-user principal ledger and use the same proportions for yield distribution.

---

## 4. Status / receipt tracking

### On-chain (read from the vault)

```solidity
// Pre-clearing: deposit details from the dNFT
DepositNftDetails memory d = IPendingPool(pendingPool).trancheDepositNftDetails(dNftId);
// d.assetAmount, d.tranche, d.epochId
// If reading reverts because the NFT is burned, the request was processed at clearing.

// FT lock details after clearing
UserLendingPoolFixedTermDeposit memory lock =
    IFixedTermDeposit(FixedTermDeposit).lendingPoolFixedTermDeposit(pool, fixedTermDepositId);
// lock.epochLockNumber, lock.epochUnlockNumber, lock.trancheShares, lock.withdrawRequested
```

### Events to subscribe to

| Event                              | When                                  | Why it matters                                                  |
| ---------------------------------- | ------------------------------------- | --------------------------------------------------------------- |
| `DepositRequested`                 | Vault calls `requestDeposit`           | Confirm queue                                                   |
| `DepositRequestAccepted`           | Clearing accepts the dNFT              | `acceptedAmount` + `trancheSharesMinted` per merged dNFT       |
| `DepositRequestRejected`           | Clearing rejects (e.g. no capacity)    | Kasu refunds USDC to the vault automatically                    |
| `FixedTermDepositLocked`           | Same clearing tx as accept             | **Capture `fixedTermDepositId`** — only on-chain handle to lock |
| `FixedTermDepositWithdrawalRequested` | Vault calls `requestFixedTermDepositWithdrawal` | Audit trail                                              |
| `FixedTermDepositInterestApplied`  | Each clearing during the lock          | Yield accruing                                                  |
| `WithdrawalRequestAccepted`        | Clearing of the unlock epoch           | `assetsWithdrawn` (USDC) + `acceptedShares` returned to vault    |

### SDK — read-only, for your UI and off-chain ops

Scope check before you wire anything up: **the SDK is for reads.** All writes — `requestDeposit`, `cancelDepositRequest`, `requestFixedTermDepositWithdrawal`, etc. — happen from your Solidity vault using the signatures in §3 and §6. The SDK exists so your frontend, ops dashboards, and event-reconciliation workers don't have to hand-roll ABIs and RPC calls.

```bash
npm install @kasufinance/kasu-sdk@2.2.1
```

```ts
import { Kasu } from "@kasufinance/kasu-sdk";

const kasu = new Kasu({ chain: "xdc-usdc", rpcUrl: "https://rpc.primenumbers.xyz/" });

// Vault's positions (flexible + FT-locked, aggregated across pools)
const positions = await kasu.portfolio.getPositions(vaultAddress);

// Historical activity — deposits, withdrawals, clearings, fills, etc.
const history = await kasu.portfolio.getTransactionHistory(vaultAddress);

// Pool / tranche metadata for your UI: APYs, capacities, limits
const strategies = await kasu.strategies.getAll();
const limits     = await kasu.strategies.calculateDepositLimits(trancheAddress);

// Epoch + clearing state
const epoch      = await kasu.deposits.getCurrentEpoch();
const isClearing = await kasu.deposits.isClearingPending(POOL_ADDRESS);
```

Anything the SDK doesn't expose: read the contracts directly. ABIs ship with the SDK (`@kasufinance/kasu-sdk/abis`) and are also on GitHub (§1).

**No subgraph.** We don't expose one for this deployment — please don't build around the assumption that there is one. If there's a specific query you need that the SDK doesn't cover, tell us and we'll add it.

**XDC RPC, briefly.** The public RPC is load-balanced and sometimes nodes lag behind by a block or two. If a read looks stale right after your vault's tx lands, give it one block and re-read on the same connection before acting on it.

### Event subscription pattern

The vault's off-chain worker should subscribe to logs on `PendingPool` and `FixedTermDeposit`, filtered by the vault address in `topics[1]`. Reconcile on:

- Every clearing run: either poll `ClearingCoordinator.lendingPoolClearingStatus(pool, epoch) == ENDED(6)` or react to `ClearingExecuted` step 6.
- Any `DepositRequestCancelled`, `FixedTermDepositUnlocked`, or `FixedTermDepositWithdrawalRequested` you didn't initiate (see §8 — the pool manager has force paths).
- Any `AllowListUpdated` event touching the vault address.

---

## 5. Epoch & clearing mechanics

| Constant                  | Value                          | How to read on-chain                                |
| ------------------------- | ------------------------------ | --------------------------------------------------- |
| Epoch duration            | 7 days (604,800 seconds)        | `SystemVariables.epochDuration()`                   |
| Clearing window           | 48 h at the end of each epoch  | `SystemVariables.clearingPeriodLength()`            |
| Epoch boundary (Base)     | Thursday 06:00 UTC              | `SystemVariables.epochStartTimestamp(epoch)`        |
| `xdc-usdc` epoch boundary | **Aligned to the same anchor as XDC AUDD (Thu 06:00 UTC).** Confirm via `epochStartTimestamp` |

```solidity
SystemVariables.currentEpochNumber();
SystemVariables.epochStartTimestamp(epoch);
SystemVariables.nextEpochStartTimestamp();
SystemVariables.isClearingTime();
```

```ts
const epoch = await kasu.deposits.getCurrentEpoch();
const isClearing = await kasu.deposits.isClearingPending(poolId);
```

**Behaviour during the 48h clearing window:** new `requestDeposit` calls are *queued for the next epoch* (not the one being cleared). Cancellations are blocked.

### How Raze knows clearing has finished

There is **no webhook**. Two equivalent options:

1. **Poll on-chain status:**
   ```solidity
   ClearingStatus s = IClearingCoordinator(ClearingCoordinator)
       .lendingPoolClearingStatus(lendingPool, epochNumber);
   // s == ENDED (6) means clearing complete for that pool/epoch
   ```
2. **Subscribe to** `ClearingExecuted(lendingPool, epoch, clearingStatus)`. Clearing progresses through 6 steps, each emitting the event. Only `clearingStatus == 6` (ENDED) means fully complete.

Once clearing finishes, the vault's positions update on-chain.

**One thing worth calling out up front:** the tranche tracks two different views of ownership for your vault.
- `balanceOf(vault)` — ERC20 custody. During an FT lock this is `0` because the shares physically sit on our `FixedTermDeposit` contract until unlock.
- `userActiveShares(vault)` — beneficial ownership. This stays pointing to your vault the whole time the lock is active. It's what Kasu uses for per-user accounting (yield attribution, ERC1155 loss-token issuance, etc.), so from a risk/economics standpoint your vault is still the shareholder of record — just with custody delegated to FT.

You don't need to care about that distinction for normal read flow. Just use one of the paths below and you'll get the right number.

**How to read your vault's position — pick one, don't combine:**

```ts
// Option A (preferred): SDK. Returns your total position across all pools and tranches,
// with active FT locks already aggregated in.
const positions = await kasu.portfolio.getPositions(vaultAddress);
```

```solidity
// Option B: direct on-chain read of a specific lock. Kasu has done the math for you —
// lock.trancheShares is already principal + accrued yield; convertToAssets gives USDC.
UserLendingPoolFixedTermDeposit memory lock =
    IFixedTermDeposit(FixedTermDeposit).lendingPoolFixedTermDeposit(pool, fixedTermDepositId);
uint256 currentUsdc = ILendingPoolTranche(lock.tranche).convertToAssets(lock.trancheShares);
```

Don't build your numbers by subscribing to events and deriving them yourself — both of the above already return final, current values. Use events only for notifications (something changed, go re-read), not as the source of truth.

### Per-end-user holdings

Kasu doesn't know about your end users — it only sees your vault. Attributing a lock's value back to individual end users is entirely your bookkeeping, not something Kasu can help with on-chain. Whatever ratio each end user has in a given `fixedTermDepositId` is yours to track and apply against the lock's current value (which you get from the SDK).

Two Kasu-side behaviours that directly affect that bookkeeping, both covered in §3:

- **Same-epoch merges** — two `requestDeposit` calls from your vault in the same epoch with the same (tranche, configId) collapse into one lock. If those two calls were for different end users, the lock backs both of them with a single unlock date and single share count.
- **Partial fills** — a dNFT that isn't fully filled at clearing carries its remainder forward and may merge with a later same-epoch deposit, further mixing end users into one lock.

---

## 6. Withdrawal flow

Each FT lock has an `epochUnlockNumber`. With `requestEpochsInAdvance = 1`:

1. **At epoch `unlockEpoch - 1`:** vault calls
   ```solidity
   ILendingPoolManager(LendingPoolManager).requestFixedTermDepositWithdrawal(
       address lendingPool,
       uint256 fixedTermDepositId
   );
   ```
   This sets `withdrawRequested = true` on the lock. No NFT minted at this stage.
2. **At epoch `unlockEpoch` clearing:** Kasu's clearing engine ends the lock and, because `withdrawRequested == true`, automatically routes the unlocked tranche shares into a **priority withdrawal** in the same clearing run. USDC + final yield arrive in the vault.
3. **Cancel:** with `cancelRequestEpochsInAdvance = 0`, a submitted request **cannot be cancelled**.

### ⚠️ No auto-rollover, no auto-withdrawal

If the vault **does not** call `requestFixedTermDepositWithdrawal` before the deadline:
- The FT lock still ends at `unlockEpoch`.
- The unlocked tranche shares are returned to the vault as **flexible** (non-locked) tranche shares.
- The vault must then call the standard `requestWithdrawal(pool, tranche, shareAmount)` to convert them back to USDC at the next clearing.

So missing the request deadline doesn't lose funds, but it adds at least one extra epoch of delay before USDC is back in the vault.

### Withdrawing flexible tranche shares (post-unlock fallback)

```solidity
uint256 shares = ILendingPoolTranche(tranche).userActiveShares(vault);
uint256 wNftId = ILendingPoolManager(LendingPoolManager).requestWithdrawal(
    address lendingPool,
    address tranche,
    uint256 shares                  // shares, NOT USDC amount
);

// To estimate USDC value pre-call:
uint256 usdcValue = ILendingPoolTranche(tranche).convertToAssets(shares);
```

Withdrawals can be partially filled if liquidity is constrained — unfilled shares stay in the wNFT and can be re-requested next epoch.

### Cancelling a pending flexible withdrawal

```solidity
ILendingPoolManager(LendingPoolManager).cancelWithdrawalRequest(lendingPool, wNftId);
// Reverts with CannotCancelRequestIfClearingIsPending() during clearing.
// Reverts with CannotCancelSystemWithdrawalRequest if the wNFT was auto-generated
// by the FT unlock path (§6.2). Those ones you can't cancel.
```

---

## 6a. Reverts worth handling explicitly

These are the custom errors you'll actually hit in production. Everything is a custom error (no revert strings), and the SDK's ABIs decode them for you.

| Error                                              | What it means for the vault                                                         |
| -------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `UserNotInAllowList(address user)`                 | Vault isn't on `KasuAllowList`. Stop and escalate to Kasu.                          |
| `UserBlocked(address user)`                        | Vault was explicitly blocked. Stop and escalate.                                    |
| `UserNotWhitelistedForFixedTermDeposit(pool, configId, user)` | Vault isn't on the per-config allowlist. Escalate to Apxium / Kasu.      |
| `FixedTermDepositDisabled(pool, configId)`         | Config got disabled. Stop new deposits; existing locks are unaffected.              |
| `InvalidTrancheForFixedTermDeposit(pool, configId, expected, got)` | Wrong tranche for this configId. Fix the call — don't just retry.   |
| `CannotCancelRequestIfClearingIsPending()`         | Clearing window is open. Try again after it closes.                                 |
| `CannotExecuteDuringClearingTime()`                | Deposit/withdraw is blocked for the 48h clearing window. Queue and retry.           |
| `RequestDepositAmountLessThanMinimumAllowed(...)`  | Below the tranche minimum. Adjust or hold.                                          |
| `RequestDepositAmountMoreThanMaximumAllowed(...)`  | Above the tranche maximum. Split the deposit or hold.                               |
| `TooManyAssetsRequested(dNftId, available, requested)` | You passed more than what's actually on the dNFT. Re-read state first.          |
| `FixedTermDepositWithdrawalAlreadyRequested(...)`  | Already requested — treat as a no-op success.                                       |
| `FixedTermDepositWithdrawalRequestTooLate(...)`    | Missed the `requestEpochsInAdvance` deadline. Shares come back as flexible — see §6. |
| `FixedTermDepositWithdrawalNotRequested(...)`      | Unlock called without a prior request. Call `requestFixedTermDepositWithdrawal` first. |
| `InvalidLendingPoolFixedTermDepositUser(...)`      | `fixedTermDepositId` doesn't belong to the vault. Don't retry — it's a data bug.    |
| `SystemPaused()`                                   | Protocol-wide pause. Retry after unpause.                                           |
| `LendingPoolIsStopped()`                           | That pool is winding down. Stop new deposits into it.                               |

If you want to match selectors manually: `keccak256(signature)[0:4]`.

---

## 7. Capacity & rates

### Per-tranche capacity

```solidity
(uint256 min, uint256 max) = ILendingPool(pool).trancheConfigurationDepositLimits(tranche);
PoolConfiguration memory cfg = ILendingPool(pool).poolConfiguration();
uint256 available = ILendingPool(pool).availableFunds();
uint256 pending = IPendingPool(pendingPool).pendingDepositAmountForCurrentEpoch();
```

```ts
const strategies = await kasu.strategies.getAll();
const limits = await kasu.strategies.calculateDepositLimits(trancheAddress);
```

### Rates (per-tranche)

```solidity
PoolConfiguration memory cfg = ILendingPool(pool).poolConfiguration();
uint256 epochRate = cfg.tranches[i].interestRate;   // 18 decimals: 1e18 = 100%
// APY = (1 + epochRate/1e18) ^ 52.17857 - 1   (52.17857 = 365.25 / 7)
```

The SDK already returns annualised APYs:

```ts
const strategies = await kasu.strategies.getAll();
// strategy.tranches[i].apy
```

Rate changes are **not pushed**. Two options:

- Poll `poolConfiguration().tranches[i].interestRate` (or the SDK equivalent) on a schedule.
- Subscribe to relevant pool-config events.

Rate changes have a built-in epoch delay (`trancheInterestChangeEpochDelay` in pool config), giving advance notice on-chain even without a push channel.

---

## 8. Operational notes

- **Capital flow.** Repayments from borrowers land in the lending pool contract itself; pool admin calls `returnDrawnFunds()` on the pool. There is no separate settlement wallet.
- **Pause behaviour.** `LendingPoolManager` has a `whenNotPaused` guard. The vault should retry on `Paused`-style reverts.
- **Allowlist revocation.** Kasu admin can revoke vault allowlist in case of incident — vault should fail gracefully on `UserNotAllowed`-style reverts.
- **Force operations.** Pool Manager has `forceCancelDepositRequest`, `forceAcceptWithdrawalRequest`, and `endFixedTermDeposit` (early termination). The vault should listen for unsolicited `FixedTermDepositUnlocked` and `DepositRequestCancelled` events and reconcile.
- **RPC.** Use `https://rpc.primenumbers.xyz/` — **not** `rpc.xdc.org`, which is unreliable (it took our own chain-50 poller down on 2026-08-24). Have a fallback ready; `https://rpc.ankr.com/xdc`, `https://rpc.xdcrpc.com` and `https://rpc.xinfin.network` all work, and we run them as an ordered failover list. Reads go through the SDK or direct contract calls — no subgraph. If you see a read that looks stale right after a tx, re-read on the next block; XDC RPC is load-balanced and individual nodes lag occasionally.
- **Loss events — two things happen.** (a) The tranche's share price drops uniformly at the loss block — `convertToAssets(shares)` instantly returns less, so your vault feels the haircut immediately on both flexible holdings and active FT locks. (b) Separately, ERC1155 loss tokens are minted to the beneficial owner (your vault) as a record of who took the loss, in case a recovery arrives later. They sit dormant with zero value on their own. If the borrower ever recovers anything, call `LendingPoolManager.claimRepaidLoss(pool, tranche, lossId)` from your vault — Kasu computes your pro-rata share and transfers USDC. Works identically whether your shares are flexible or FT-locked at the time (loss tokens follow beneficial ownership, not ERC20 custody). Partial recoveries are fine — call as often as repayments land. Tokens are non-transferable. Your vault must implement `IERC1155Receiver`.

---

## 9. Open questions for Raze

1. **One vault for all 3 pools, or one vault per pool?** Affects allowlist scope on Kasu's side and per-config whitelist setup.
3. **Lock duration UX.** Will each pool have a single FT duration (e.g. POOL_A = 26w, POOL_B = 52w, POOL_C = 52w), or do you need multiple FT configs per pool to expose duration choice to your users?
4. **Materialisation delay.** Confirm acceptance that share + lock issuance happens at the *next* epoch's clearing (1–7 days after the vault's `requestDeposit`). The dNFT is the receipt during that window. Vault UX should reflect this (e.g. "pending" share state).
5. **Per-end-user reconciliation.** Confirm the vault implements the per-`fixedTermDepositId` ledger described in §3 to handle same-epoch merges.
6. **Withdrawal automation.** Will the vault auto-submit `requestFixedTermDepositWithdrawal` 1 epoch before each lock's unlock, or do end users opt in? See §6 for the no-auto-rollover behaviour.
7. **Yield distribution cadence.** Kasu accrues yield every epoch but pays it at unlock. Will Raze distribute to end users at unlock only, or mark-to-market each Kasu epoch via `convertToAssets`?
8. **Failure handling.** What should the vault do on a reverted `requestDeposit` (allowlist revoked, pool paused, capacity exhausted)? Refund end user immediately, or queue and retry next epoch?
9. **Capacity comms.** Weekly capacity per tranche — push from Apxium (email/Slack), API endpoint, or polling the on-chain views above? **Owner: Leon.**
10. **Rate-change comms.** Kasu publishes rate changes on-chain with an epoch-delay; do you also want an off-channel notification before they hit?

---

## 10. Our side of the checklist

Mirrors the 🚧 TODOs at the top. This is what we (Kasu + Apxium) need to do before you can run end-to-end.

- [ ] Apxium creates the 3(?) USDC pools → we paste pool / tranche / `PendingPool` addresses into §1.
- [ ] Apxium sets up the FT config + per-config whitelist (your vault) + withdrawal window on each pool → we fill `fixedTermConfigId`, lock duration, and rate in §1 / §2.
- [ ] Kasu multisig adds your vault(s?) to `KasuAllowList`.
- [ ] We read `epochStartTimestamp` on `xdc-usdc` and write the confirmed boundary into §5.
- [ ] From your side: confirm the vault address(es) we should whitelist.

---
