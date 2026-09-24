# Yield Payout (non-compounding) — design

**Status:** draft / design. Captures the agreed architecture for letting selected lenders receive
their yield as a claimable USDC "drop" each clearing instead of compounding it into their position.
Applies to **both** variable (flexible) and fixed-term (FT) lenders.

> Prerequisite reading: `docs/fixed-term-deposits.md` (FT mechanics, custody pattern) and the
> "Tranche ownership model" section of `CLAUDE.md` (`balanceOf` vs `userActiveShares`).

---

## 1. Summary

Today all yield **compounds**: each clearing, `LendingPool._applyTrancheInterest` mints LendingPool
tokens to the tranche (raising NAV), booked as `userOwedAmount`. A lender only realizes that value by
withdrawing. This feature lets a **whitelisted "payout group"** instead receive their per-epoch yield
as a claimable USDC balance they can pull from an escrow at any time — principal stays invested.

Mechanism (per the agreed model):
- **a)** On clearing, the managers **burn the shares** representing the payout group's epoch yield, and
- **b)** move the equivalent **USDC into an escrow** that users withdraw from whenever they want.

The whole thing is **O(1) per clearing** (one aggregate burn + one accumulator update — no per-user
loop, no per-user USDC sends), which is what makes it scale.

---

## 2. The core constraint (why funding policy matters)

Yield in Kasu is an **IOU from the borrower, not cash**. Interest is minted as LendingPool tokens and
tracked in `userOwedAmount`; real USDC only enters via `repayOwedFunds`. (Observed live: TaxPay held
**$1.18** USDC while owing lenders **$3.94M**.)

Therefore an escrow that users withdraw real USDC from must be **funded with real USDC**. The agreed
funding policy is **Option A — the borrower pays coupons regularly**: every clearing, the borrower must
deliver the payout group's yield in cash, so the escrow is always fully funded and payout lenders can
always claim in full immediately. This is the classic periodic-coupon (bond) model and is the only
policy that makes "regular automatic payout" a real promise rather than a best-effort one.

---

## 3. Locked design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Opt-in, manager-set, whitelist-only.** `mapping(address => YieldMode)` (`Compound` default / `Payout`). | Mirrors `KSULocking.isFeeRecipientEnabled` + permissioned setter. Default preserves current behavior (upgrade-safe). |
| 2 | **Payout shares held in a separate custodial** (`YieldDistributor`), FT-style. | One share holder → aggregate burns, no per-user loop. Reuses the existing FT custody pattern. |
| 3 | **Pull-based claim via accumulator.** USDC sits in `YieldEscrow`; users `withdrawYield()` anytime. | MasterChef-style `accYieldPerShare`/`debt` (already proven in `KSULocking`). O(1) accrual + O(1) claim. |
| 4 | **Funding = Option A** (borrower pays coupons each period; escrow always fully funded). | Only policy that delivers *regular* payout; natural fit for FT coupons. |

---

## 4. Architecture

```
                         opt-in (manager, whitelisted)
  Lender ───────────────────────────────────────────────► YieldMode = Payout
     │  (tranche shares move into custody, FT-style)
     ▼
  ┌─────────────────┐   each clearing (after Step 1 interest)   ┌──────────────┐
  │ YieldDistributor│  1. compute group yield Y                  │   Borrower   │
  │  (custodial)    │  2. borrower funds Y USDC ───────────────► │ pays coupon  │
  │ holds payout    │  3. burn ΔS shares + reconcile pool books  └──────┬───────┘
  │ group's shares  │  4. accYieldPerPrincipal += Y/totalPrincipal      │ Y USDC
  └────────┬────────┘                                                   ▼
           │ principal stays invested                           ┌──────────────┐
           │                                                    │  YieldEscrow │
  Lender ──┴──── withdrawYield() (pull, KYC-checked, anytime) ◄─┤  holds USDC  │
                                                                └──────────────┘
```

Components:
- **`YieldMode` flag** — per user (variable) / per lock (FT). Manager-set, whitelist-only.
- **`YieldDistributor`** — custodies the payout group's tranche shares (one ERC20 holder); runs the
  per-clearing burn; maintains the accumulator and per-user principal/debt.
- **`YieldEscrow`** — holds coupon USDC; serves `withdrawYield()` claims. (May be folded into the
  distributor; kept conceptually separate for clarity and auditability.)

New module, **not** added to `LendingPool`/`PendingPool` (the latter is already near the EIP-170 limit —
the repo had to enable `via_ir` to keep it under). Storage in the proxies stays append-only.

---

## 5. Accounting model (the math)

Work in **asset (USDC) terms** for the payout group — principal value is held constant and the *growth*
is skimmed. Let `NAV = tranche.convertToAssets(1e18)`.

**State (per tranche, in `YieldDistributor`):**
```
mapping(address => uint256) principalAssets;   // user principal in USDC, constant between interactions
uint256 totalPrincipalAssets;                  // Σ principalAssets
uint256 accYieldPerPrincipal;                  // scaled 1e24, Σ of epoch growth factors
mapping(address => uint256) yieldDebt;         // MasterChef reward-debt
mapping(address => uint256) accruedYield;      // settled-but-unclaimed USDC (set on principal changes)
```

**Invariant:** `tranche.convertToAssets(distributorShares) == totalPrincipalAssets`
(the distributor's custodied shares are always worth exactly the group's aggregate principal).

**Per clearing (after Step 1 interest applied), per tranche:**
```
currentValue = tranche.convertToAssets(distributorShares)   // grew due to NAV rise
Y            = currentValue - totalPrincipalAssets          // = the group's epoch yield (USDC)
if (Y > 0) {
    // Option A: borrower delivers Y USDC into YieldEscrow (precondition — see §6)
    ΔS = tranche.previewWithdraw(Y)                          // shares representing the yield
    // burn ΔS from the distributor + reconcile pool books so NAV is untouched for everyone else:
    //   - redeem/burn ΔS tranche shares
    //   - burn Y LendingPool tokens   (cf. forceImmediateWithdrawal: _burn(address(this), assetAmount))
    //   - userOwedAmount -= Y         (cf. repayOwedFunds: the coupon settles the owed claim)
    accYieldPerPrincipal += Y * 1e24 / totalPrincipalAssets
}
// totalPrincipalAssets is left unchanged → invariant restored (distributorShares fell by ΔS)
```
Burning `ΔS = Y/NAV` shares is exactly the amount that leaves the **Compound** group's NAV invariant
(derivation: `ΔS = Y/NAV` ⟹ post-burn NAV == pre-burn NAV). So the payout skim never affects compounders.

**Per-user claim (O(1), pull):**
```
claimable(user) = accruedYield[user]
                + principalAssets[user] * accYieldPerPrincipal / 1e24 - yieldDebt[user]
```
On any principal change (opt-in/out, deposit, withdraw, loss): **settle** — move the live term into
`accruedYield[user]`, then reset `principalAssets[user]` and `yieldDebt[user] = principalAssets * acc / 1e24`.

`withdrawYield()` pays `claimable` from `YieldEscrow` (KYC-checked), zeroes the settled portion.

> Loss case (`Y < 0`, NAV fell): no coupon that epoch; the group's principal is impaired. The accumulator
> must **not** accrue negative yield — instead `totalPrincipalAssets`/`principalAssets` absorb the loss
> (the distributor's shares are simply worth less). Exact loss-apportionment is an open item (§12).

---

## 6. Funding model — Option A (coupons)

The borrower must fund the epoch's coupon **in cash** as part of clearing. Enforcement options (decide in
detailed design):
- **(Recommended) Direct coupon funding.** A `fundCoupon(pool, tranche, amount)` (or the clearing step
  itself) pulls `Y` USDC from the borrower straight into `YieldEscrow`, **separate from `repayOwedFunds`**
  (coupons are distinct from principal liquidity — exactly like a bond). The share-burn then reconciles the
  tranche books (`burn ΔS` + `userOwedAmount -= Y`). This keeps coupon payment off the pool's withdrawal
  liquidity entirely.
- **(Variant) Redeem from pool liquidity.** Skip the direct payment; redeem `ΔS` shares to USDC from the
  pool and route to escrow. Simpler, but competes with ordinary withdrawals and requires the borrower to
  have pre-funded the pool via `repayOwedFunds`.

Either way, **if the coupon is unfunded the payout step cannot finalize** — a deliberate forcing function.
Open question: should an unfunded coupon block *all* of clearing, or only the payout step (clearing
proceeds, coupon rolls/accrues to next epoch with a flag)? See §12.

---

## 7. Clearing integration

Hook a new batched step **after Step 1 (interest applied), before Step 2 (priorities)** — yield is fully
accrued at that point and requests haven't been processed yet. Reuse the existing batched-task framework
(`TaskStatus` + `nextIndexToProcess`) — though with the custodial/aggregate model the work is O(1) per
tranche, so batching is mostly a formality (loop is over *tranches*, not users).

Triggered by the existing clearing caller (`ROLE_POOL_CLEARING_MANAGER` via `LendingPoolManager.doClearing`).
The step: for each tranche with `totalPrincipalAssets > 0`, run the §5 computation and the §6 funding check.

---

## 8. Variable (flexible) lenders

- Opt-in is **per user, per tranche** (`YieldMode`).
- On opt-in: `transferFrom(user → YieldDistributor)` their tranche shares; set `principalAssets[user] =
  convertToAssets(shares)`; bump `totalPrincipalAssets`; init `yieldDebt`.
- Each clearing they participate in the aggregate skim (§5). Their principal value stays flat; the base
  NAV growth is dropped to escrow.
- Opt-out / withdraw principal: settle yield, redeem `principalAssets[user]` worth of shares back to them
  (or to a withdrawal request if liquidity-gated).

## 9. FT (fixed-term) lenders — the natural coupon

This is the cleanest case and needs the least new machinery:
- FT shares are **already custodied** in `FixedTermDeposit`, and the per-lock coupon is **already computed
  each clearing** in `applyFixedTermInterests → _applyFixedRateInterests`.
- Opt-in is **per lock** (a `payoutCoupons` flag on the lock, or per-(user,config)). Today the loop *mints
  the premium as shares into the lock* (Layer B) and base accrues via NAV (Layer A). For a payout lock,
  instead **route the full coupon (base + premium) to `YieldEscrow`** and credit the user's claim, keeping
  `lock.trancheShares` flat at principal.
- Principal stays locked to maturity; coupons pay out on schedule. Textbook fixed-term coupon bond.
- Funding: Option A is intrinsic here — the guaranteed rate *is* a coupon the borrower must fund.

## 10. Opt-in / opt-out lifecycle

- **Enable (manager, whitelisted user):** validate whitelist → move shares to custody → set principal,
  debt → bump `totalPrincipalAssets`.
- **Disable / withdraw:** settle outstanding yield to `accruedYield` → return principal shares (direct if
  liquid, else via a withdrawal request) → decrement `totalPrincipalAssets`.
- **Deposit more while in Payout mode:** settle, then increase `principalAssets`/`totalPrincipalAssets`.
- All principal-changing ops must **settle first** (snapshot the accumulator) to keep claims exact.

## 11. Contract & interface sketch

```solidity
enum YieldMode { Compound, Payout }

interface IYieldDistributor {
    // --- admin / manager (whitelist-gated) ---
    function setYieldMode(address user, address tranche, YieldMode mode) external; // ROLE_POOL_MANAGER
    function setPayoutWhitelist(address user, bool allowed) external;              // ROLE_POOL_MANAGER

    // --- clearing (ROLE_POOL_CLEARING_MANAGER / ClearingCoordinator) ---
    function applyYieldPayout(address pool, address tranche, uint256 targetEpoch) external;

    // --- borrower (Option A funding) ---
    function fundCoupon(address pool, address tranche, uint256 amount) external;   // ROLE_POOL_FUNDS_MANAGER

    // --- lender (pull) ---
    function withdrawYield(address tranche, uint256 amount) external returns (uint256); // KYC-checked
    function claimable(address user, address tranche) external view returns (uint256);

    // --- views ---
    function yieldMode(address user, address tranche) external view returns (YieldMode);
    function principalAssets(address user, address tranche) external view returns (uint256);
}
```

## 12. Cross-cutting concerns / open items

- **Unfunded-coupon behavior (decide):** block all clearing, or only the payout step (accrue + flag)?
- **Loss handling (decide):** payout shares custodied → a tranche loss hits the distributor. Either keep
  `userActiveShares` with users (FT-style) so loss-tokens still mint per-user, or have the distributor
  re-apportion. Ensure a loss epoch accrues **no** positive yield and correctly impairs `principalAssets`.
- **KYC at claim time:** a payout user later de-KYC'd/blocked (`KasuAllowList`) — `withdrawYield()` must
  respect the allowlist (hold the claim until re-cleared).
- **Storage / size:** new module, append-only proxy storage; keep out of `LendingPool`/`PendingPool`.
- **Events / tax / subgraph:** emit coupon-funded + yield-dropped + claimed events. The tax tooling
  (`scripts/reporting`) assumes compounding; payout changes the basis and needs new events + a subgraph
  entity (cf. `UserLendingPoolTrancheFixedTermDepositLock`).
- **Dust / min-claim threshold:** weekly coupons on small positions are tiny — add a min-claim and/or
  carry-forward to avoid fragmenting escrow accounting.
- **Reentrancy / CEI:** `withdrawYield` does an external USDC transfer — guard it.
- **Rounding:** `1e24`-scaled accumulator; define rounding direction (favor the pool) and reconcile dust.
- **Interaction with `forceImmediateWithdrawal` / `endFixedTermDeposit`:** ensure those settle a payout
  position's outstanding yield before moving principal.

## 13. Phasing

1. **FT first** (smallest delta): per-lock `payoutCoupons` flag; route the existing coupon to escrow;
   reuse FT custody. Proves the escrow + claim + Option-A funding end to end.
2. **Variable**: add `YieldDistributor` custody + opt-in for flexible lenders.
3. **Hardening**: loss apportionment, KYC-on-claim, tax/subgraph events, dust thresholds.

---

### Decisions captured
- Funding: **Option A** (borrower pays coupons regularly; escrow always funded).
- Custody: **separate custodial** for payout-mode shares (FT-style), for scalability.
- Opt-in: `mapping(address => YieldMode)`, manager-set, whitelist-only.
- Distribution: **pull** from escrow via MasterChef-style accumulator (no per-user sends).
