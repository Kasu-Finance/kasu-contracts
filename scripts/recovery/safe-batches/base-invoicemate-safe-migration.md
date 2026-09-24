# Base Payment Finance — clearing catch-up, sweep the locked InvoiceMate Safe, migrate roles

Batch: `base-invoicemate-safe-migration.json`
Execute from: **Kasu multisig `0xC3128d734563E0d034d3ea177129657408C09D35`** (Base).

## Background

InvoiceMate's borrower Safe `0x793DAEec8293A6869b42cc56988b6780f458d4f3` is 3-of-3 and one
signer key was lost, so it can no longer transact. It holds ~4,937.92 USDC and is still the
pool's **draw recipient** plus holder of `ROLE_POOL_MANAGER`, `ROLE_POOL_FUNDS_MANAGER` and
`ROLE_POOL_CLEARING_MANAGER`. Replacement Safe: `0x156aea25b5C62210Ea42F0A08791253688705eC9`
(Safe v1.4.1, 2-of-3).

Separately, clearing on this pool stalled after epoch 115: `nextLendingPoolClearingEpoch` is
116 while `currentEpochNumber()` is 119, so `isLendingPoolClearingPending` is latched true and
every `verifyClearingNotPending` path (including `repayOwedFunds`) reverts.

## ⚠ Execution window — Thu 2026-09-24 06:00 UTC to Tue 2026-09-29 06:00 UTC

`isClearingTime()` is `nextEpochStartTimestamp() - now <= clearingPeriodLength`, and
`clearingPeriodLength` is 2 days — so the window is open **Tue 06:00 → Thu 06:00 UTC** each week.

`isLendingPoolClearingPending` returns true when `nextTargetEpoch == currentEpoch` **and** the
window is open and that epoch has not ENDED. So once the catch-up brings the pool level with the
current epoch, the pending flag re-latches for as long as the window is open, and
**`repayOwedFunds` (tx 5) reverts — taking the whole atomic batch with it.**

Execute only while `isClearingTime()` is `false`. After the epoch rolls to 120 on Thu
2026-09-24 06:00 UTC, all four epochs 116-119 are past epochs and short-circuit safely. If
execution slips past Tue 2026-09-29 06:00 UTC the window reopens and the batch must be
regenerated with epoch 120 appended and re-timed.

## Why this order is load-bearing

1. **Clearings before the sweep** — `repayOwedFunds` carries `verifyClearingNotPending`, and
   the pool must be level with the current epoch *outside* the clearing window (see above).
2. **Sweep before the revokes** — `repayOwedFunds` requires the *repaymentAddress* to hold
   `ROLE_POOL_FUNDS_MANAGER`. Revoking first permanently strands the USDC.
3. **Draw recipient before the revokes** — otherwise a later draw sends funds to a Safe that
   can neither spend them nor be swept again.
4. **Grant before revoke** — no window where the pool has no manager.

The batch is atomic, which is the point: there is no state in which the old roles are gone but
the sweep did not land.

## What the catch-up clearings actually do

`targetEpoch < currentEpoch` sets `isPastClearingTime`, which short-circuits to `ENDED` after
step 1. They apply interest only — **no request processing, no step-5 draw**. `drawAmount=0`
and `isConfigOverridden=false` belt-and-braces the same point.

Applying 4 epochs (116-119) of interest adds roughly **11,299 USDC** to what the borrower owes
(~1,130 fees / ~10,169 lenders). That is interest already economically accrued, but it is booked
on execution and it raises `feesOwedAmount` **before** the sweep — so ~2,239 of the swept
4,937.92 clears fees and only ~2,699 reduces principal and stays in the pool as its only
available liquidity. Make sure InvoiceMate has been told this before they authorise the sweep.

## Pre-flight (re-read immediately before signing)

```bash
RPC=https://mainnet.base.org
cast call 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 "balanceOf(address)(uint256)" 0x793DAEec8293A6869b42cc56988b6780f458d4f3 --rpc-url $RPC
cast call 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 "allowance(address,address)(uint256)" 0x793DAEec8293A6869b42cc56988b6780f458d4f3 0xE1Be322323a412579b4A09fB08ff4bfcA12096B5 --rpc-url $RPC
cast call 0x2cF12A6d91fa4bEB5a4C17589a03e78F88f57DE2 "nextLendingPoolClearingEpoch(address)(uint256)" 0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE --rpc-url $RPC
cast call 0x193Bb02A24F5562b58fEB86550e6f09Bb6c41f69 "currentEpochNumber()(uint256)" --rpc-url $RPC
cast call 0x193Bb02A24F5562b58fEB86550e6f09Bb6c41f69 "isClearingTime()(bool)" --rpc-url $RPC
```

- **Safe balance** must still be `4937916389`. It can only rise (the Safe cannot send), and a
  higher balance just leaves dust — but if it changed, bump tx 4's `amount` to match.
- **`nextLendingPoolClearingEpoch`** must still be `116`. If a clearing ran in the meantime,
  drop the already-done epochs from txs 1-4.
- **`currentEpochNumber`** must be `120`. The batch clears 116-119 as past epochs; if the epoch
  has not yet rolled, epoch 119 would be a *real* clearing (steps 2-5, needs processed loyalty
  levels and correct batch sizes) — do not sign.
- **`isClearingTime` must be `false`.** If true, tx 5 reverts and the batch fails atomically.

## Verify the encoded calls

```bash
cast decode-calldata "doClearing(address,uint256,uint256,uint256,uint256,(uint256,uint256[],uint256,uint256),bool)" <tx1-4 data>
```

Selectors, checked against the compiled ABI: `doClearing` `44a871af`, `repayOwedFunds`
`53266c98`, `updateDrawRecipient` `cceb171a`, `grantLendingPoolRole` `60450ee1`,
`revokeLendingPoolRole` `0bc4b290`.

Role hashes: `ROLE_POOL_MANAGER` `0x3e891da8…`, `ROLE_POOL_FUNDS_MANAGER` `0x3329bd6c…`,
`ROLE_POOL_CLEARING_MANAGER` `0xe9bdd900…`. `ROLE_POOL_ADMIN` is **not** granted — the old Safe
never held it.

## Simulate before signing

Tenderly, or an Anvil fork:

```bash
anvil --fork-url https://mainnet.base.org --chain-id 8453 --port 8546
```

Gas is the main unknown: 4 clearings + a sweep + 7 role/config writes in one MultiSend. If it
does not fit, split into batch A (txs 1-5, through the sweep) and batch B (txs 6-12) and
**confirm A landed before proposing B** — never the reverse, since B revokes the role that A
depends on.

## Post-execution checks

```bash
RPC=https://mainnet.base.org
cast call 0x2cF12A6d91fa4bEB5a4C17589a03e78F88f57DE2 "isLendingPoolClearingPending(address)(bool)" 0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE --rpc-url $RPC   # false
cast call 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 "balanceOf(address)(uint256)" 0x793DAEec8293A6869b42cc56988b6780f458d4f3 --rpc-url $RPC                      # 0
cast call 0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE "availableFunds()(uint256)" --rpc-url $RPC                                                                   # ~2698
cast call 0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868 "hasLendingPoolRole(address,bytes32,address)(bool)" 0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE 0x3329bd6c227be4e42b89b31e00759830ade608c3d5d453d53614f7fe5d902461 0x156aea25b5C62210Ea42F0A08791253688705eC9 --rpc-url $RPC  # true
cast call 0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868 "hasLendingPoolRole(address,bytes32,address)(bool)" 0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE 0x3329bd6c227be4e42b89b31e00759830ade608c3d5d453d53614f7fe5d902461 0x793DAEec8293A6869b42cc56988b6780f458d4f3 --rpc-url $RPC  # false
```

## Deliberately NOT in this batch

`forceImmediateWithdrawal` of accrued yield to `0x7b4a6f5f…`. Left to InvoiceMate to request
later. Note the pool cannot currently fund it: the yield above 900k is ~15,023 after a 4-epoch
catch-up, against ~2,699 of available liquidity — roughly 18% of the ask.
