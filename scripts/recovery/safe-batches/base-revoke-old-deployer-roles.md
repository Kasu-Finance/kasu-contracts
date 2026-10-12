# Base: hand two unused pools to Apxium, revoke every role of the old deployer

**File:** `base-revoke-old-deployer-roles.json` · **Executing Safe:** Kasu multisig
`0xC3128d734563E0d034d3ea177129657408C09D35` (Base, threshold 3) · **Target:** Base
KasuController `0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868`

**Status (2026-10-12): NOT YET PROPOSED.** The Safe nonce was 24 when this was written.

## Why

The old deployer `0x0e7e0a898ddBbE859d08976dE1673c7A9F579483` had its `DEFAULT_ADMIN_ROLE`
revoked, but it still held these roles (read on-chain 2026-10-11, surfaced by the admin
deployment-health page):

| Where | Old deployer holds | Others holding the same roles |
|---|---|---|
| Global | `ROLE_LENDING_POOL_CREATOR` | Kasu multisig |
| `0xe621eC2A0De3C9EAb96e088256b60c59FFF87607` Professional Fee Funding - Accounting Firms (live) | all 4 pool roles | Apxium pool admin + pool manager Safes |
| `0x54A98e1baeD45854789B0448ED1277997D64FFFE` Invoice Financing - Accounting Firms (Directus-disabled, not stopped) | all 4 pool roles | Apxium pool admin on 3 roles; **sole** `ROLE_POOL_FUNDS_MANAGER` |
| `0xA30D35aa4eBb885c9c7Bb9de766266CD6a221eBe` Taxation Funding (Directus-disabled, not stopped) | all 4 pool roles | **nobody** |

Owner decision (2026-10-12): revoke everything; the two unused pools go to Apxium.

## What this does (22 calls, in this order)

1. **9 × `grantRole(bytes32,address)`**: the two unused pools get the layout of the live Base
   pools. `ROLE_POOL_ADMIN` and `ROLE_POOL_CLEARING_MANAGER` go to the Apxium pool admin Safe
   `0x7adf999af5E0617257014C94888cf98c4584E5E9`. `ROLE_POOL_MANAGER` and
   `ROLE_POOL_FUNDS_MANAGER` go to both that Safe and the Apxium pool manager Safe
   `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2`. The pool-scoped role id is
   `keccak256(abi.encode(pool, ROLE))`.
   - Invoice Financing: MANAGER → manager Safe; FUNDS_MANAGER → admin Safe + manager Safe.
   - Taxation Funding: all four roles as above (6 grants).
2. **12 × `revokeLendingPoolRole(pool, role, deployer)`**: all 4 pool roles on the three pools.
3. **1 × `revokeRole(ROLE_LENDING_POOL_CREATOR, deployer)`**.

Grants come first, so no pool is ever without an admin.

**Why `grantRole` and not `grantLendingPoolRole`:** `grantLendingPoolRole` is gated by
`onlyPoolAdminOrFactory`. On Taxation Funding the only pool admin is the old deployer, so the
Kasu multisig cannot call it. Every pool-scoped role and `ROLE_LENDING_POOL_CREATOR` has
`DEFAULT_ADMIN_ROLE` as its admin (`getRoleAdmin` returns `0x00`, checked on-chain), and the
Kasu multisig holds that role. So OpenZeppelin's `grantRole` works. It emits `RoleGranted`
but not `LendingPoolRoleGranted`, which is harmless: `hasLendingPoolRole` reads the same
role id. `revokeLendingPoolRole` is gated by `onlyAdminOrPoolAdmin`, which the Kasu admin
passes. The batch is idempotent.

## Pre-flight

```bash
RPC=https://mainnet.base.org
CTRL=0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868
cast call --rpc-url $RPC $CTRL 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 0xC3128d734563E0d034d3ea177129657408C09D35   # true
```

In the Safe Transaction Builder, confirm every tx's **To** is the Base KasuController above.

## Dry-run (Anvil fork of Base, block 52,501,243, 2026-10-12)

All 22 calls succeeded from the impersonated Kasu Safe. Reproduce:

```bash
anvil --fork-url https://mainnet.base.org --chain-id 8453 --port 8557 --auto-impersonate
# per tx in the JSON (grantRole/revokeRole take role,account; revokeLendingPoolRole takes pool,role,account):
cast send --rpc-url http://127.0.0.1:8557 --unlocked --from 0xC3128d734563E0d034d3ea177129657408C09D35 \
  0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868 "<method signature>" <args>
```

## Post-check (the fork matched exactly; run again on mainnet after execution)

```bash
DEP=0x0e7e0a898ddBbE859d08976dE1673c7A9F579483
ADM=0x7adf999af5E0617257014C94888cf98c4584E5E9
MGR=0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2
cast call --rpc-url $RPC $CTRL 'hasRole(bytes32,address)(bool)' $(cast keccak ROLE_LENDING_POOL_CREATOR) $DEP   # false
for P in 0xe621eC2A0De3C9EAb96e088256b60c59FFF87607 0x54A98e1baeD45854789B0448ED1277997D64FFFE 0xA30D35aa4eBb885c9c7Bb9de766266CD6a221eBe; do
  for R in ROLE_POOL_ADMIN ROLE_POOL_CLEARING_MANAGER ROLE_POOL_MANAGER ROLE_POOL_FUNDS_MANAGER; do
    H=$(cast keccak $R)
    echo "$P $R dep=$(cast call --rpc-url $RPC $CTRL 'hasLendingPoolRole(address,bytes32,address)(bool)' $P $H $DEP) adm=$(cast call --rpc-url $RPC $CTRL 'hasLendingPoolRole(address,bytes32,address)(bool)' $P $H $ADM) mgr=$(cast call --rpc-url $RPC $CTRL 'hasLendingPoolRole(address,bytes32,address)(bool)' $P $H $MGR)"
  done
done
```

Expected on every pool: `dep=false` everywhere. ADMIN and CLEARING_MANAGER show
`adm=true mgr=false`; MANAGER and FUNDS_MANAGER show `adm=true mgr=true`. After execution,
the admin deployment-health page (kad.kasu.finance) shows Base with no FAILs.
