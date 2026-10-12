# Base: hand two unused pools to Apxium, revoke every role of the old deployer

**File:** `base-revoke-old-deployer-roles.json` (41 calls) · **Check:** `base-revoke-old-deployer-roles.check.sh`
· **Executing Safe:** Kasu multisig `0xC3128d734563E0d034d3ea177129657408C09D35` (Base, 3-of-5)
· **Targets:** KasuController `0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868` and
LendingPoolManager `0xE1Be322323a412579b4A09fB08ff4bfcA12096B5`

**Status (2026-10-12): NOT YET PROPOSED.** The Safe nonce was 24 when this was written.

## Why

The old deployer `0x0e7e0a898ddBbE859d08976dE1673c7A9F579483` lost `DEFAULT_ADMIN_ROLE` but
still held these roles. They were found by the admin deployment-health page and confirmed on-chain.

| Where | Old deployer holds | Other holders | Draw recipient |
|---|---|---|---|
| Global | `ROLE_LENDING_POOL_CREATOR` | Kasu multisig | — |
| `0xe621eC2A0De3C9EAb96e088256b60c59FFF87607` Professional Fee Funding - Accounting Firms (live, fully withdrawn) | all 4 pool roles | Apxium Safes (live layout) | Apxium pool manager Safe |
| `0x54A98e1baeD45854789B0448ED1277997D64FFFE` Invoice Financing - Accounting Firms (unused, holds 0 USDC) | all 4 pool roles | Apxium admin Safe on 3 roles; **plus all 4 granted in 2024 to the Professional Fee Funding POOL CONTRACT address** (a mis-paste found in the `RoleGranted` history, never revoked) | Apxium **admin** Safe |
| `0xA30D35aa4eBb885c9c7Bb9de766266CD6a221eBe` Taxation Funding (unused, holds 0 USDC) | all 4 pool roles | **nobody** | **the old deployer** |

Owner decision (2026-10-12): revoke everything; the two unused pools go to Apxium; both unused
pools draw to the Kasu multisig.

## What the 41 calls do, in order

- **A (2):** `grantRole` makes the Kasu Safe `ROLE_POOL_ADMIN` on Invoice Financing and Taxation
  Funding, temporarily. `updateDrawRecipient` requires the pool admin role.
- **B (2):** `LendingPoolManager.updateDrawRecipient` points both pools at the Kasu Safe.
- **C (18):** `grantRole` sets the live Base Apxium layout on all three pools.
  `ROLE_POOL_ADMIN` and `ROLE_POOL_CLEARING_MANAGER` go to the Apxium pool admin Safe
  `0x7adf999af5E0617257014C94888cf98c4584E5E9`. `ROLE_POOL_MANAGER` and
  `ROLE_POOL_FUNDS_MANAGER` go to it and to the Apxium pool manager Safe
  `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2`. The grants are idempotent, and most are
  already held; re-granting them protects against a role being stripped between proposal and
  execution. The others replace roles the deployer held, some of them alone.
- **D (13):** `revokeLendingPoolRole` removes all 4 pool roles of the old deployer on each
  pool, and `revokeRole` removes its `ROLE_LENDING_POOL_CREATOR`.
- **D2 (4):** `revokeLendingPoolRole` removes the 4 stray Invoice Financing roles held by
  the Professional Fee Funding pool contract address.
- **E (2):** `revokeLendingPoolRole` drops the Kasu Safe's temporary pool admin.

Grants precede revokes, so no pool is ever without an admin.

**Why `grantRole` and not `grantLendingPoolRole`:** `grantLendingPoolRole` is gated by
`onlyPoolAdminOrFactory`, and the Kasu Safe is not a pool admin. Every pool-scoped role id
(`keccak256(abi.encode(pool, ROLE))`) and `ROLE_LENDING_POOL_CREATOR` has
`DEFAULT_ADMIN_ROLE` as its admin (`getRoleAdmin` returns `0x00`, checked on-chain), and the
Kasu Safe holds that role. `hasLendingPoolRole` reads the same role id.
**But** OZ `grantRole`/`revokeRole` emit `RoleGranted`/`RoleRevoked`, not
`LendingPoolRoleGranted`/`Revoked`. The backend's privileged-event alerts watch only the
latter, so the 22 grants and the pool-creator revoke in this batch will **not** page
`#kasu-alerts`. The 18 `revokeLendingPoolRole` calls will. That alerting gap is tracked
separately (kasu-backend). Announce the execution in the channel yourself.

**Full role history:** the controller is not enumerable, so the holders were taken from every
`RoleGranted`/`RoleRevoked` event for these 13 role ids since the controller's deployment
(block 15,486,216 to 52,503,770; 31 events). Apart from the Apxium Safes, the Kasu Safe and
the old deployer, the only holder is the stray pool-contract address, revoked in D2.

## Pre-flight (run right before signing — collecting signatures can take days)

```bash
scripts/recovery/safe-batches/base-revoke-old-deployer-roles.check.sh pre
```

It must end with `ALL OK`. It re-reads every role of the old deployer, the Kasu Safe and the
stray address on the three pools, the pool-creator role, the three draw recipients, and the
pause flag. In the Safe Transaction Builder, check that tx 3 and tx 4 go to the
LendingPoolManager above, and every other call goes to the KasuController.

## Dry-run (Anvil fork of Base, block 52,503,874, 2026-10-12)

All 41 calls succeeded from the impersonated Kasu Safe, and `check.sh post` against the fork
ended `ALL OK`. To reproduce:

```bash
anvil --fork-url https://mainnet.base.org --chain-id 8453 --port 8558 --auto-impersonate
# for each tx in the JSON: cast send --unlocked --from 0xC3128d734563E0d034d3ea177129657408C09D35 <to> "<method(types)>" <args>
scripts/recovery/safe-batches/base-revoke-old-deployer-roles.check.sh post http://127.0.0.1:8558
```

## Post-check (on mainnet, after execution)

```bash
scripts/recovery/safe-batches/base-revoke-old-deployer-roles.check.sh post
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

The first must end `ALL OK`. Then the admin deployment-health page (kad.kasu.finance) shows
Base with no FAILs.
