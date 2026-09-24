# Fixed-Term Deposits (FT) — mechanics, yield, withdrawal & operations

Reference for how fixed-term deposits work in the Kasu lending protocol: the data model,
the share-ownership model, how positions are created, how yield is credited, how they are
withdrawn, and the operational levers (and their gotchas).

> Code references use `Contract.function()` plus file paths. A few line numbers are given for
> the trickiest spots — treat them as approximate; the source is authoritative.

Primary contracts:
- `src/core/lendingPool/FixedTermDeposit.sol` — the FT engine (configs, locks, lock/unlock, interest application)
- `src/core/lendingPool/LendingPool.sol` — base/fixed interest application, `forceImmediateWithdrawal`, asset transfers
- `src/core/lendingPool/LendingPoolManager.sol` — all caller-facing entry points (role-gated)
- `src/core/lendingPool/LendingPoolTranche.sol` — the ERC4626 tranche token (`balanceOf`, `userActiveShares`)
- `src/core/lendingPool/PendingPool.sol` — deposit/withdrawal request queue; auto-locks accepted FT deposits at clearing

---

## 1. What an FT deposit is

A fixed-term deposit locks a depositor's **tranche shares** for a fixed number of epochs in
exchange for a **guaranteed per-epoch interest rate** (typically a premium over the tranche's
floating base rate). The locked shares are custodied by the `FixedTermDeposit` contract for the
duration of the lock.

Two on-chain structures (`src/core/interfaces/lendingPool/IFixedTermDeposit.sol`):

```solidity
struct FixedTermDepositConfig {
    address tranche;              // which tranche this config applies to
    uint64  epochInterestRate;    // guaranteed rate, per EPOCH, 1e18 = 100% (INTEREST_RATE_FULL_PERCENT)
    uint16  epochLockDuration;    // lock length in epochs
    FixedTermDepositStatus status;// Disabled | WhitelistedOnly | Everyone
}

struct UserLendingPoolFixedTermDeposit {  // a "lock"
    address user;
    uint16  fixedTermDepositConfigId;
    uint32  epochLockNumber;      // epoch the lock started
    uint32  epochUnlockNumber;    // epochLockNumber + config.epochLockDuration
    bool    withdrawRequested;
    uint256 trancheShares;        // CURRENT locked shares (grows each epoch via premium top-ups)
}
```

- **Configs** are per-pool, addressed by `configId`. `configId` starts at **1** (`addLendingPoolTrancheFixedTermDeposit`
  does `count++; id = count`); `configId 0` is unused. Count: `lendingPoolFixedTermDepositConfigCount(pool)`.
- **Locks** are per-pool, addressed by `lockId`. The active set is `lendingPoolFixedTermDepositIds(pool)`
  (an array maintained with **swap-and-pop** on removal — see §10).
- `epochInterestRate` is **per epoch**. Epochs are weekly, so annualize by ~×52 (compounded).
  Example: `2848512117642616` (= 2.848512e15 / 1e18) = 0.2848512%/epoch ≈ ~15.9% APY.

---

## 2. Share ownership: `balanceOf` vs `userActiveShares` (read this first)

`LendingPoolTranche` tracks two *different* views of ownership. Conflating them is the #1 source
of FT reasoning/operational errors.

| View | What it is | During an FT lock |
|------|-----------|-------------------|
| `balanceOf(user)` | ERC20 custody. Moves on `transfer`/`transferFrom`. | **0** — the shares sit on the `FixedTermDeposit` contract (`balanceOf(FT)`). |
| `userActiveShares(user)` | Beneficial ownership. Only mutated by `tranche.deposit()` (mint) and `removeUserActiveShares()` (redeem). | **Unchanged** — she remains the beneficial owner throughout the lock. |

The ERC20 `_update`/`_transfer` hook is **not** overridden to sync `userActiveShares`, so a plain
`transferFrom(user → FT)` (which is exactly what locking does, `FixedTermDeposit._lockFixTermDeposit`)
moves only the ERC20 balance. `userActiveShares[user]` stays put; `userActiveShares[FT]` stays `0`.

**Consequences for an FT-locked depositor — every ERC20/ERC4626 "custody" read shows nothing:**
- `balanceOf(user)` = 0
- `maxRedeem(user)` = 0, `maxWithdraw(user)` = 0 (both derive from `balanceOf`)
- The wallet "asset tokens" view shows no tranche tokens
- BUT `userActiveShares(user)` and `convertToAssets(userActiveShares(user))` show the **full** position,
  and the subgraph reports the full position too (it tracks beneficial ownership — see §11).

> **Do not conclude "she has no shares" from `balanceOf`/`maxRedeem`/the wallet view.** Check
> `userActiveShares` and enumerate her FT locks. The sum of her locks' `trancheShares` reconciles to
> `userActiveShares` to the wei (for a 100%-locked depositor).

---

## 3. How shares become FT-locked (entry points)

There are exactly two ways a lock is created; both funnel into `FixedTermDeposit._lockFixTermDeposit`,
which does `transferFrom(user, FT, shares)` and writes the lock struct.

1. **Automatic (at clearing)** — `FixedTermDeposit.lockFixedTermDepositAutomatically`, called by
   `PendingPool` during the clearing step when a **deposit request that selected an FT config** is
   accepted. The freshly minted tranche shares are locked. Lock starts at the accepted epoch.

2. **Manual (self-service)** — `LendingPoolManager.lockDepositForFixedTerm(pool, tranche, amount, configId)`
   → `FixedTermDeposit.lockFixedTermDepositManually`. Locks **already-owned flexible** tranche shares.
   - The manager passes **`msg.sender`** as the user, so **only the depositor can lock their own shares —
     an operator/admin CANNOT lock on a user's behalf** (by design; it's the user's custody).
   - Prerequisite: the user must `approve` the `FixedTermDeposit` contract on the tranche ERC20 first.
   - Lock starts at `currentEpochNumber()`; unlock = start + `config.epochLockDuration`.
   - Gated by `verifyClearingNotPending` and `verifyFixedTermDepositParameters` (config exists, not
     `Disabled`, tranche matches, and — if `WhitelistedOnly` — the user is on the config allowlist).

After locking: `balanceOf(user)` drops, `balanceOf(FT)` rises, `userActiveShares(user)` is **unchanged**.

---

## 4. Yield model — two independent layers

Both layers are applied **per epoch, during clearing**.

**Layer A — base tranche yield (every shareholder, locked or not).**
`LendingPool._applyTrancheInterest` mints pool tokens to the tranche each clearing, which raises the
tranche **NAV** (assets-per-share). Because it lifts NAV, *every* holder of tranche shares earns it
automatically — whether the shares sit in the user's wallet, in the `FixedTermDeposit` contract, or
anywhere. Net of `SystemVariables.performanceFee()`. Event: `InterestApplied`.

**Layer B — the fixed-term premium (locked shares only).**
`LendingPool._applyFixedRateInterests` (≈ `LendingPool.sol:953`) computes, per lock, the difference
between the config's `fixedInterestRate` and the tranche's `baseTrancheInterestRate`:
- `fixed > base`: mints the **difference** as extra shares and adds them **into the lock**
  (`lock.trancheShares` grows each epoch). This is the premium.
- `fixed < base`: **removes** shares from the lock (claws the excess back to base).
- `fixed == base`: nothing.
Net of performance fee. Event: `FixedInterestDiffApplied` (and `FixedTermDepositInterestApplied` for the
new share count).

**Implications:**
- Yield is credited **incrementally each epoch**, not as a lump at maturity. A lock's `trancheShares`
  already reflects all premium accrued through the last clearing.
- A locked position's effective rate ≈ base APY + premium APY. Un-locking reverts the shares to the
  **base** rate (Layer A continues; Layer B stops). Nothing already credited is clawed back on un-lock.

---

## 5. Clearing-time processing & maturity

During clearing, `FixedTermDeposit.applyFixedTermInterests` iterates the pool's locks and, for each,
calls `LendingPool.applyFixedRateInterests` to apply Layer B for that epoch (updating `lock.trancheShares`).

At maturity (`epochUnlockNumber <= targetEpoch`), the same loop calls `_endFixedTermDeposit`:
- transfers the lock's `trancheShares` back to the user's **wallet** (`balanceOf`), and
- deletes the lock; then
- if `withdrawRequested` was set, it creates a **priority withdrawal** for those shares
  (`PendingPool.requestPriorityWithdrawal`) so they convert to USDC at that clearing.

So a matured lock with no withdrawal request simply returns the shares to the user as **flexible**
tranche shares (still deposited, now earning only the base rate).

---

## 6. Withdrawing an FT position

### 6a. `forceImmediateWithdrawal` cannot touch a locked position directly
`LendingPool.forceImmediateWithdrawal` (≈ `LendingPool.sol:664`) does
`tranche.redeem(shares, pool, user)` — an ERC4626 redeem that **burns from the user's `balanceOf`**.
For a locked position `balanceOf(user) == 0`, so it reverts (`maxRedeem` is also 0). There is **no**
variant that reaches FT-custodied shares. To force-withdraw a locked position you must first move the
shares back to the wallet (§6c).

### 6b. Term-respecting path (user self-service)
`LendingPoolManager.requestFixedTermDepositWithdrawal(pool, lockId)` →
`FixedTermDeposit.requestFixedTermDepositWithdrawal`. **User-initiated** (passes `msg.sender`; the FT
contract verifies the caller owns the lock — operators cannot request on a user's behalf). It only
sets `withdrawRequested = true`; the payout is auto-created as a priority withdrawal at the unlock
epoch's clearing (§5).
- Subject to a timing guard `_verifyWithdrawalActionTime(currentEpoch, unlockEpoch, requestEpochsInAdvance)`:
  the request must be made early enough — `requestEpochsInAdvance` epochs **before** unlock — else it
  reverts `FixedTermDepositWithdrawalRequestTooLate`. With `requestEpochsInAdvance == 0` it can be made
  any time before unlock.
- Reversible via `cancelFixedTermDepositWithdrawalRequest` (subject to `cancelRequestEpochsInAdvance`).
- The advance/cancel windows live in `LendingPoolWithdrawalConfiguration { requestEpochsInAdvance,
  cancelRequestEpochsInAdvance }` (`FixedTermDeposit.lendingPoolWithdrawalConfiguration(pool)`).

### 6c. Premature unlock (operator)
`LendingPoolManager.endFixedTermDeposit(pool, lockId, arrayIndex)` → `FixedTermDeposit.endFixedTermDeposit`.
`ROLE_POOL_MANAGER`, **no maturity guard** (doc: "Prematurely end the fixed term deposit"), gated by
`verifyClearingNotPending`. It returns the **entire** lock's shares to the user's wallet and deletes the
lock. **You cannot partially unwind a lock.** After this, `forceImmediateWithdrawal` works on the now-flexible
shares (subject to pool liquidity — §7).
- Early-ending **forfeits only the future Layer-B premium** for the remaining epochs of that lock;
  Layer-A base yield continues, and nothing already credited is lost.
- Because the whole lock must be ended, to free `X` from a depositor with multiple locks, end the
  **smallest lock that covers `X`** — that minimizes the principal pushed off its fixed rate.

---

## 7. Liquidity reality — force-withdrawals need USDC *in the pool*

`forceImmediateWithdrawal` pays **physical USDC** via `_transferAssets(user, amount)` →
`USDC.safeTransfer(user, amount)` **from the pool contract's own balance**
(`src/core/AssetFunctionsBase.sol`). The **caller** (e.g. a pool-manager multisig) holding USDC does
**not** help — it is only the tx sender, it does not fund the payout.

RWA pools are typically **fully drawn** to the borrower, so `USDC.balanceOf(pool)` ≈ 0 while
`userOwedAmount()` is large. In that state, an immediate withdrawal of any material size reverts with
USDC's legacy string **`ERC20: transfer amount exceeds balance`** — for **any** tranche, regardless of
whether shares are FT-locked. (A "Junior works but Senior doesn't" report is usually a misread: Senior
fails the *share* gate because it's FT-locked; at a large amount, *both* tranches then fail the *USDC*
gate.)

To fund a payout, the borrower repays USDC **into the pool**:
`LendingPoolManager.repayOwedFunds(pool, amount, repaymentAddress)` — `ROLE_POOL_FUNDS_MANAGER` for
**both** `msg.sender` and `repaymentAddress`; pulls USDC from `repaymentAddress` into the pool; capped at
`userOwedAmount + feesOwedAmount`. (`repaymentAddress` must `approve` the `LendingPoolManager` first.)
For drawn pools the normal exit is the **epoch withdrawal flow**, not immediate force-withdrawal.

---

## 8. Config & allowlist management (operator)

All `ROLE_POOL_MANAGER`, via `LendingPoolManager`:
- `addLendingPoolTrancheFixedTermDeposit(pool, tranche, epochLockDuration, epochInterestRate, whitelistedOnly)`
  — creates a new config (`whitelistedOnly ? WhitelistedOnly : Everyone`; never `Disabled` on create).
  Validates `epochLockDuration > 0` and the rate via `_verifyTrancheInterestRate`. Returns the new `configId`.
- `updateLendingPoolTrancheFixedInterestStatus(pool, configId, status)` — flip a config between
  `Disabled` / `WhitelistedOnly` / `Everyone`.
- `updateFixedTermDepositAllowlist(pool, configId, users[], isAllowed[])` — required to let specific users
  use a `WhitelistedOnly` config. Read with `FixedTermDeposit.fixedTermDepositsAllowlist(pool, configId, user)`.
- `updateLendingPoolWithdrawalConfiguration(pool, {requestEpochsInAdvance, cancelRequestEpochsInAdvance})`.

A manual lock starts at the **current epoch**, so a fresh config with
`epochLockDuration = (targetUnlockEpoch − currentEpoch)` lets a re-lock land on a specific maturity (e.g.
to match a depositor's other locks). Note: re-locking flexible shares is a **user** action (§3) — the
operator can create/allowlist the config, but the depositor must run the `approve` + `lockDepositForFixedTerm`
themselves.

---

## 9. Roles matrix

| Action | Caller | Role |
|--------|--------|------|
| Deposit with FT (auto-lock at clearing) | depositor | KYC/allowlist + config allowlist if `WhitelistedOnly` |
| `lockDepositForFixedTerm` (lock existing flexible shares) | **depositor only** | config allowlist if `WhitelistedOnly` |
| `requestFixedTermDepositWithdrawal` / `cancelFixedTermDepositWithdrawalRequest` | **depositor only** | owns the lock |
| `endFixedTermDeposit` (premature unlock) | operator | `ROLE_POOL_MANAGER` |
| `forceImmediateWithdrawal` | operator | `ROLE_POOL_MANAGER` |
| `addLendingPoolTrancheFixedTermDeposit` / status / allowlist / withdrawal-config | operator | `ROLE_POOL_MANAGER` |
| `repayOwedFunds` (fund the pool) | operator | `ROLE_POOL_FUNDS_MANAGER` (caller **and** repaymentAddress) |

All mutating calls are `whenNotPaused`; most FT mutations are also `verifyClearingNotPending` (blocked
while a clearing for that pool is in progress — check `ClearingCoordinator.isLendingPoolClearingPending(pool)`).

---

## 10. Inspecting a depositor's FT position

**On-chain (tranche):**
- `balanceOf(user)` — custody (0 if fully FT-locked)
- `userActiveShares(user)` — beneficial ownership (the real position)
- `convertToAssets(shares)` — USDC value of a share amount

**On-chain (FixedTermDeposit):**
- `lendingPoolFixedTermDepositIds(pool)` — active lock ids
- `lendingPoolFixedTermDeposit(pool, lockId)` — the lock struct (user, configId, lock/unlock epoch, withdrawRequested, `trancheShares`)
- `lendingPoolFixedTermConfig(pool, configId)` / `lendingPoolFixedTermDepositConfigCount(pool)`
- `lendingPoolWithdrawalConfiguration(pool)` / `fixedTermDepositsAllowlist(pool, configId, user)`

**Subgraph (`kasu-subgraph`):**
- `UserLendingPoolTrancheFixedTermDepositLock` — per lock: `lockId`, `trancheShares`, `initialTrancheShares`,
  `epochLockStart`, `epochLockEnd`, `isWithdrawalRequested`, `isLocked`, `user`, `lendingPool`.
- `LendingPoolTrancheUserDetails.shares` — the aggregate beneficial position (≈ `userActiveShares`), with
  locks under `userLendingPoolTrancheFixedTermDepositLocks`. Filter `User` by **lowercase** address.

The subgraph's per-lock `trancheShares` should reconcile to the on-chain lock struct to the wei.

---

## 11. Operator gotchas / checklist

- **`balanceOf == 0` ≠ no position.** It usually means FT-locked. Verify with `userActiveShares` + locks.
- **Locks can't be partially unwound.** `endFixedTermDeposit` ends the *whole* lock; to free a small
  amount, end the smallest lock that covers it (minimizes forfeited premium).
- **`arrayIndex` shifts.** `lendingPoolFixedTermDepositIds` is maintained with swap-and-pop, so the index
  of a given `lockId` changes when other locks are removed. Re-read the array before each
  `endFixedTermDeposit`; do multiple ends one at a time. (`endFixedTermDeposit` self-heals a wrong index
  by scanning for the id, but only while the id still exists.)
- **Operators can't lock or request-withdraw on a user's behalf.** `lockDepositForFixedTerm` and
  `requestFixedTermDepositWithdrawal` are depositor-only. The operator can `endFixedTermDeposit` and
  `forceImmediateWithdrawal` (push funds out), and create/allowlist configs.
- **Force-withdrawals are liquidity-gated.** Confirm `USDC.balanceOf(pool) ≥ amount` (or `repayOwedFunds`
  first). The multisig holding USDC is irrelevant unless repaid into the pool.
- **Clearing window.** Most FT mutations revert if `isLendingPoolClearingPending(pool)`; many use
  `currentEpochNumber()` / `currentRequestEpoch()`. Re-check immediately before executing — and prefer
  batching dependent operator calls atomically.
- **Always fork-simulate the real payout** (e.g. `anvil --fork-url <rpc> --auto-impersonate`, impersonate
  the role-holder, run the full sequence), not just the role/share checks — the USDC-transfer leg is where
  drawn-pool withdrawals actually fail.
