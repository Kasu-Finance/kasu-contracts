# xdc AUDD: grant pool-manager roles to the Apxium draw-wallet Safe

**File:** `xdc-audd-grant-pool-manager-roles.json` · **Executing Safe:** Apxium pool admin
`0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112` · **Target:** AUDD KasuController
`0xe81D1C0E031da0E357928ED19aA1EbF6A2f5C904`

**Status (read on-chain 2026-09-24): PARTLY EXECUTED — 2 of 6.** Only the Taxation Funding
pool (`0x20F4…7800`) has both roles; Whole Ledger (`0x3b7c…A9`) and Professional Fee
(`0xEDa5…fad`) have neither. Re-run the post-check before re-proposing, and send only the
four missing grants.

## What this does

Six `grantLendingPoolRole` calls granting `ROLE_POOL_MANAGER` and `ROLE_POOL_FUNDS_MANAGER`
to the Apxium pool manager / draw-wallet Safe `0x21567eA21b14BEd14657e9725C2FE11C7be942B1`
on each of the 3 AUDD pools:

| Pool | Name |
|---|---|
| `0x20F42FB45f91657aCf9528b99a5a16d0229C7800` | Taxation Funding - Diversified Businesses |
| `0x3b7cb493Aa22f731DB2ab424D918e7375E00F6A9` | Whole Ledger Funding - Professional Services Firms |
| `0xEDa50C91a8c4CA8A83652b8542c0b3BD00A71fad` | Professional Fee Funding - Accounting Firms |

## Why

On Base, xdc-usdc and Plume the pool manager Safe holds `ROLE_POOL_MANAGER` +
`ROLE_POOL_FUNDS_MANAGER` on every Apxium pool (verified on-chain 2026-09-02). On XDC AUDD it
holds **no** pool role: the Feb 2026 grant transactions targeted
`0x7923837dC93d897E12696e0F4FD50b51FBacf693`, which is the **Plume** KasuController and has
no code on XDC, so they were silent no-ops. First symptom: the `repayOwedFunds` batch proposed
from `0x2156…` (Safe nonce 8, 2026-09-02) reverts with
`AccessControlUnauthorizedAccount(0x2156…, ROLE_POOL_FUNDS_MANAGER)`.

`grantLendingPoolRole` is gated by `onlyPoolAdminOrFactory`, so only `0x880Aa2…`
(`ROLE_POOL_ADMIN` on all 3 pools) can execute this. The Kasu multisig cannot.

## Pre-flight

```bash
RPC=https://rpc.primenumbers.xyz/
CTRL=0xe81D1C0E031da0E357928ED19aA1EbF6A2f5C904
ADM=0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112
ROLE_ADMIN=$(cast keccak ROLE_POOL_ADMIN)
for P in 0x20F42FB45f91657aCf9528b99a5a16d0229C7800 0x3b7cb493Aa22f731DB2ab424D918e7375E00F6A9 0xEDa50C91a8c4CA8A83652b8542c0b3BD00A71fad; do
  echo "$P admin-has-ROLE_POOL_ADMIN=$(cast call --rpc-url $RPC $CTRL 'hasLendingPoolRole(address,bytes32,address)(bool)' $P $ROLE_ADMIN $ADM)"
done
```
All three must print `true`. In the Safe Transaction Builder, confirm every tx's **To** is the
AUDD controller above (not the Plume one) before signing.

## Dry-run (Anvil fork, done 2026-09-02 at block 106,748,519)

All 6 grants succeeded; afterwards `0x2156…` holds exactly MANAGER + FUNDS_MANAGER (not ADMIN,
not CLEARING) on all 3 pools; the pending nonce-8 repay batch then executed successfully
(feesOwed 9,008.909997 → 0.909997 AUDD, FeeManager +9,008 AUDD). Reproduce:

```bash
anvil --fork-url https://rpc.primenumbers.xyz/ --chain-id 50 --port 8546 --auto-impersonate --compute-units-per-second 30
# then, per tx in the JSON:
cast send --rpc-url http://127.0.0.1:8546 --unlocked --from 0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112 \
  0xe81D1C0E031da0E357928ED19aA1EbF6A2f5C904 "grantLendingPoolRole(address,bytes32,address)" <pool> <role> 0x21567eA21b14BEd14657e9725C2FE11C7be942B1
```

## Post-check

```bash
for P in 0x20F42FB45f91657aCf9528b99a5a16d0229C7800 0x3b7cb493Aa22f731DB2ab424D918e7375E00F6A9 0xEDa50C91a8c4CA8A83652b8542c0b3BD00A71fad; do
  for R in ROLE_POOL_MANAGER ROLE_POOL_FUNDS_MANAGER; do
    echo "$P $R=$(cast call --rpc-url $RPC $CTRL 'hasLendingPoolRole(address,bytes32,address)(bool)' $P $(cast keccak $R) 0x21567eA21b14BEd14657e9725C2FE11C7be942B1)"
  done
done
```
All six must be `true`. Then `npx hardhat --network xdc run scripts/smokeTests/validateDeploymentComplete.ts`.
