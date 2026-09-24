# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kasu is an RWA (Real World Asset) private credit lending platform built on Solidity. It connects DeFi investors with lending entities for business loan origination. The platform uses permissioned lending pools with epoch-based clearing, signature-gated deposits (Didit-verified lenders; signatures minted by kasu-backend with AWS KMS and verified on-chain through `KasuKycSigner`), and a KSU token-based loyalty system.

## Build & Test Commands

```bash
# Install dependencies
npm install           # All dependencies (OpenZeppelin + deployment scripts)

# Build
forge build           # Compile Solidity contracts

# Testing
forge test                           # Run all tests
forge test --mt <test_name>          # Run single test by name
forge test --mc <ContractName>       # Run tests matching contract name
forge test -vvvv                     # Verbose output with traces

# Coverage
forge coverage --report lcov
genhtml lcov.info --branch-coverage -o coverage  # Generate HTML report

# Format
forge fmt             # Format Solidity code

# Documentation
forge doc --build     # Generate documentation
```

## Deployment

```bash
# 1. Setup environment file (copy and fill in private keys)
cp scripts/_env/.env.example scripts/_env/.base.env
# Edit .base.env with DEPLOYER_KEY, ADMIN_KEY, etc.

# 2. Local development
npm run node:local                                    # Start local Hardhat node
npx hardhat --network localhost deploy               # Deploy to local node

# 3. Production deployment (deployment mode set in chains.ts)
npx hardhat --network base deploy    # Full deployment with KSU token (deploymentMode: 'full')
npx hardhat --network plume deploy   # Lite version without token (deploymentMode: 'lite')
npx hardhat --network xdc deploy     # Lite version without token (deploymentMode: 'lite')
```

Deployment mode (full/lite) and protocol fee receiver are now chain-specific in `scripts/_config/chains.ts`.
Environment files are loaded from `scripts/_env/.{network}.env` (e.g., `.base.env`, `.plume.env`).
See `scripts/_env/.env.example` for all available options.

**External TVL Tracking**: The main deployment includes `KasuPoolExternalTVL` (ERC1155 contract for tracking off-chain TVL per pool). Set `EXTERNAL_TVL_BASE_URI` env variable if you need custom metadata URI.

## ProxyAdmin Management

Kasu uses OpenZeppelin's TransparentUpgradeableProxy pattern. With OpenZeppelin Contracts v5 / hardhat-upgrades v3, **each proxy has its own dedicated ProxyAdmin contract** (not a shared one). This is by design for security isolation.

### Why Per-Proxy ProxyAdmins?
- **Security isolation**: A compromised ProxyAdmin only affects one proxy, not the entire system
- **OpenZeppelin v5 design**: The hardhat-upgrades plugin enforces this pattern
- **Unified ownership**: All ProxyAdmins share the same owner address, so administration is still centralized

### Admin Scripts
```bash
# View all ProxyAdmins and their owners
npx hardhat --network base run scripts/admin/printProxyAdmins.ts

# Transfer all ProxyAdmin ownership to a new address (e.g., multisig)
NEW_PROXY_ADMIN_OWNER=0x... npx hardhat --network base run scripts/admin/transferAllProxyAdminOwnership.ts

# Validate deployment: check bytecode matches source, Etherscan verification status
npx hardhat --network base run scripts/admin/validateDeployment.ts
npx hardhat --network plume run scripts/admin/validateDeployment.ts

# Auto-verify unverified contracts that match source
AUTO_VERIFY=true npx hardhat --network base run scripts/admin/validateDeployment.ts

# Note: Deployment mode read from chains.ts. Works with both Etherscan and Blockscout explorers.

# Smoke tests: validate roles, ownership, and configuration (run after deployment)
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

### Deployment Validation
The `validateDeployment.ts` script checks all deployed contracts:
- **Bytecode comparison**: Compares on-chain bytecode with compiled artifacts (strips metadata hash)
- **Etherscan verification**: Checks if implementation contracts are verified on block explorer
- **Upgrade eligibility**: Reports whether mismatched contracts can be upgraded (proxies) or need redeployment
- **Auto-verification**: With `AUTO_VERIFY=true`, attempts to verify unverified contracts that match source

### Upgrading Contracts
When running `deploy.ts` with `DEPLOY_UPDATES=true` on an existing deployment:
- The script uses the existing proxy addresses from the deployment file
- Upgrades are performed through each proxy's individual ProxyAdmin
- The signer must be the ProxyAdmin owner (typically the admin account)

## Dependencies

Solidity dependencies are managed via npm and vendored files (not git submodules):

| Dependency | Location | Notes |
|------------|----------|-------|
| OpenZeppelin Contracts | `node_modules/@openzeppelin/contracts/` | v5.0.2 (requires Solidity ^0.8.20, compatible with 0.8.23) |
| OpenZeppelin Upgradeable | `node_modules/@openzeppelin/contracts-upgradeable/` | v5.0.2 |
| NexeraID Sig Gating | `vendor/nexera/` | 2 vendored files for KYC signature verification |
| forge-std | `lib/forge-std/` | Foundry testing library (git submodule) |

Import remappings are configured in `remappings.txt`:
```
@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/
@openzeppelin/contracts-upgradeable/=node_modules/@openzeppelin/contracts-upgradeable/
NexeraIDSigGatingContracts/=vendor/nexera/
forge-std/=lib/forge-std/src/
```

## Architecture

### Core Contracts (`src/core/`)

**Lending Pool System** (`src/core/lendingPool/`):
- `LendingPoolManager.sol` - Entry point for all lending pool interactions
- `LendingPoolFactory.sol` - Creates new lending pools with proxy pattern
- `LendingPool.sol` - Ledger of pool balances (also ERC20 token representing total pool value)
- `PendingPool.sol` - Manages pending deposit/withdrawal requests, issues dNFT/wNFT NFTs
- `LendingPoolTranche.sol` - ERC4626 vault for tranche shares, handles ERC1155 impairment receipts
- `FixedTermDeposit.sol` - Locks deposits for fixed duration with guaranteed yields

**Clearing System** (`src/core/clearing/`):
- `ClearingCoordinator.sol` - Orchestrates clearing for all pools
- `ClearingSteps.sol` - Abstract contract extended by PendingPool for clearing execution
- `PendingRequestsPriorityCalculation.sol` - Calculates user request priority (step 2)
- `AcceptedRequestsCalculation.sol` - Clearing algorithm for accepted amounts (step 3)
- `AcceptedRequestsExecution.sol` - Executes accepted requests (step 4)

**Supporting Contracts**:
- `SystemVariables.sol` - Global system config (epoch, KSU price, fees)
- `UserManager.sol` - Calculates user loyalty levels
- `FeeManager.sol` - Distributes platform fees (ecosystem fees to rKSU holders)
- `KasuAllowList.sol` - KYC verification for deposits
- `UserLoyaltyRewards.sol` - KSU rewards based on liquidity and loyalty

### Locking System (`src/locking/`)
- `KSULocking.sol` - KSU token locking with proportional fee distribution, extends rKSU
- `rKSU.sol` - Non-transferable receipt token for locked KSU
- `KSULockBonus.sol` - Bonus KSU distribution for lockers

### Access Control (`src/shared/access/`)
- `KasuController.sol` - Administration, role management, system pause
- `Roles.sol` - Role definitions (ROLE_KASU_ADMIN, ROLE_POOL_ADMIN, ROLE_POOL_MANAGER, etc.)

### Token (`src/token/`)
- `KSU.sol` - ERC20 Kasu token with permit and burn

### Lite Variants
Files ending in `Lite.sol` are simplified versions for deployment without token-related functionality.

## Key Concepts

**Epochs**: Time periods between clearings. Deposits/withdrawals are queued during an epoch and processed at clearing.

**Tranches**: Each lending pool can have multiple tranches with different risk-return profiles.

**Clearing Process**: Multi-step process (priority calculation → accepted amounts calculation → execution) that processes queued requests at epoch boundaries.

**Loyalty Levels**: Users earn priority in clearing based on KSU token locking commitment.

## Tranche ownership model — `userActiveShares` vs `balanceOf`

`LendingPoolTranche` tracks two different views of ownership, and conflating them is a
common source of reasoning errors:

- **`balanceOf(user)` — ERC20 custody.** Standard ERC4626/ERC20 balance. Moves freely
  on `transfer`/`transferFrom`. During an FT lock it sits on `FixedTermDeposit`, not
  on the original depositor.
- **`userActiveShares[user]` — beneficial ownership.** A separate mapping that is only
  mutated by `tranche.deposit(...)` (on mint) and `removeUserActiveShares(...)` (on
  redeem). The ERC20 `_update` path is **not** overridden to sync this mapping, so
  `transfer`/`transferFrom` do not move `userActiveShares` — they only move ERC20
  balance.

**Consequence:** when `FixedTermDeposit._lockFixTermDeposit` calls
`transferFrom(user, FT, shares)` (`FixedTermDeposit.sol:618`), only the ERC20 balance
moves. `userActiveShares[user]` remains unchanged; `userActiveShares[FT]` stays `0`.
The depositor remains the beneficial owner throughout the lock.

This matters for:
- **ERC1155 loss-token minting** (`LendingPoolTrancheLoss.sol:275-283`): iterates
  `_trancheUsers` and mints against `userActiveShares`. Loss tokens therefore go to
  the beneficial owner (the depositor / integrating vault), **not** to the FT custody
  contract.
- **Loss recovery via `claimRepaidLoss`**: works directly for FT-locked depositors.
  No stranded funds, no special forwarding path needed.
- **Yield-diff top-ups** (`LendingPool.sol:989-991`): extra shares are minted by
  calling `tranche.deposit(..., user)` which correctly increments
  `userActiveShares[user]` before being transferred into FT for custody.

**When documenting this to integrators:** `convertToAssets(userActiveShares(vault))`
gives the total beneficial position (flexible + FT-locked); `balanceOf(vault)` gives
only the uncustoodied portion. For per-lock reads, `lock.trancheShares` is the
authoritative count and `convertToAssets(lock.trancheShares)` gives current USDC
value.

Regression test pinning this behaviour: `test_ftDepositLoss_recoveryWorksForFTDepositor`
in `test/unit/core/LendingPoolLossTest.sol`.

**Full fixed-term-deposit reference:** see `docs/fixed-term-deposits.md` for the complete FT model —
config/lock data structures, the two yield layers (base NAV vs fixed premium), create/lock/withdraw
entry points and which are operator vs depositor-only, the `forceImmediateWithdrawal` liquidity gate
(`repayOwedFunds`), config/allowlist management, the roles matrix, and the operator gotcha checklist.

## KYC/KYB Verification (Didit + KasuKycSigner)

Deposits are gated by a signature that `KasuAllowList.verifyUserKyc()` checks on-chain
through the vendored NexeraID `TxAuthDataVerifier` (the verifier code and the
`setNexeraIDSigner` name are legacy; the vendor is not — ComPilot/Nexera was
decommissioned 2026-08-27). The flow since the 2026-08-27 cutover:

```
Frontend → kasu-backend `POST /kyc/signature` (reads OUR Didit status store; fails closed unless Approved)
        → AWS KMS `alias/kasu-kyc-signer` signs
        → Frontend appends signature + blockExpiration to TX calldata
        → `KasuAllowList.verifyUserKyc()` → `_verifyTxAuthData()` validates on-chain
```

**The registered signer is `KasuKycSigner` (`src/core/KasuKycSigner.sol`, ERC-1271), one
per chain:** Base `0x19798De0…`, XDC AUDD `0x3EB700d2…`, XDC USDC `0x21baeA02…` (Plume
`0x43E1b2D2…`, retired). It wraps the KMS public key; **key rotation = `setSigningKey`
on that contract from the Kasu multisig** — `KasuAllowList.setNexeraIDSigner` is not
touched again. Rollback Safe batches: `scripts/deploy/safe-batches/`.

⚠ `scripts/_config/chains.ts` still carries `nexeraIdSigner: 0x29A75f22…` — the
decommissioned ComPilot `NexeraIDSignerManager` — for every chain. A fresh deployment
would register a dead signer: point it at that chain's `KasuKycSigner` (or set
`NEXERA_ID_SIGNER`) before running `deploy`.

**Key contracts:**
- `KasuAllowList.sol` - Extends `TxAuthDataVerifierUpgradeable` from vendored NexeraID contracts
- `KasuKycSigner.sol` - ERC-1271 signer holding the KMS public key (`setSigningKey`)
- `vendor/nexera/BaseTxAuthDataVerifier.sol` / `TxAuthDataVerifierUpgradeable.sol` - verifier only

## Testing Patterns

Tests use Foundry's `forge-std/Test.sol`. Base utilities in `test/unit/_utils/`:
- `BaseTestUtils.sol` - Common setup with MockUSDC, predefined test addresses (alice, bob, carol, etc.)
- `LendingPoolTestUtils.sol` - Full lending pool test setup with all contracts
- `LockingTestUtils.sol` - KSU locking test utilities

Test naming convention: `test_<feature>_<scenario>`

## Important Constants

- `FULL_PERCENT = 100_00` (100% with 2 decimals)
- `INTEREST_RATE_FULL_PERCENT = 1e18` (100% with 16 decimals)
- `KSU_PRICE_MULTIPLIER = 1e18`
- Solidity version: `0.8.23`
- Optimizer runs: 200 (Foundry), 800 (Hardhat, with 200 for PendingPool)

## Networks

Configured networks: localhost, hardhat, base-sepolia, base (mainnet), xdc, xdc-apothem, plume

## Tax Report Generation

Generate per-depositor tax invoices (JSON + PDF) from on-chain data.

### Usage

```bash
# Step 1: Generate JSON invoice
BASE_RPC_URL=https://base.gateway.tenderly.co/<key> \
DEPOSITOR_ADDRESS=0x... \
TAX_YEAR=2025 \
  npx hardhat --network base run scripts/reporting/generateTaxInvoice.ts

# Step 2: Generate PDF from the JSON
npx ts-node scripts/reporting/generateTaxPdf.ts
# Or specify a specific JSON file:
npx ts-node scripts/reporting/generateTaxPdf.ts scripts/reporting/output/tax-invoice-<addr>-<year>.json
```

### What It Collects

- **Deposits/withdrawals**: From `DepositRequestAccepted` / `WithdrawalRequestAccepted` events on each pool's PendingPool
- **Yield per epoch**: From `InterestApplied` events on each LendingPool, prorated by user's share of `userActiveShares / totalSupply` at the clearing block
- **Fixed-term deposit interest**: From `FixedInterestDiffApplied` events (per-user)
- **Opening/closing balances**: From `LendingPoolTranche.convertToAssets(userActiveShares)` at year-start/end blocks
- **Reconciliation**: Total yield is derived from balance sheet (`closing - opening - deposits + withdrawals`) and per-epoch records are proportionally adjusted to sum exactly

### Notes

- Requires an archive RPC node (Tenderly recommended — supports large block ranges for `eth_getLogs`)
- Strategy names and pool addresses are hardcoded in the script for Base mainnet
- Output goes to `scripts/reporting/output/` (gitignored)
- PDF uses puppeteer (`npm install --save-dev puppeteer`)
- Runtime: ~5 minutes per depositor (mostly historical state queries for yield)

### Key Files

| File | Purpose |
|------|---------|
| `scripts/reporting/generateTaxInvoice.ts` | On-chain data collection → JSON |
| `scripts/reporting/generateTaxPdf.ts` | JSON → HTML → PDF |
| `scripts/reporting/output/` | Generated files (gitignored) |

---

## April 2026 security upgrade (deployed on all chains 2026-04-24, `f8d2d45`)

- **Reward caps on Base** are seeded at `maxRewardPerUserPerBatch = maxBatchTotalReward =
  1_000 KSU` (1e21 wei). Retune via `setRewardCaps` (Kasu multisig, `ROLE_KASU_ADMIN`)
  once the KSU token launches and weekly emission volume stabilises: target
  `perUser ≈ 2× largest observed`, `perBatch ≈ 1.5× largest observed`.
- **Residual cosmetic drift:** `AcceptedRequestsCalculation`, `ClearingCoordinator` and
  `LendingPool` on Base show SOURCE DRIFT on Basescan — bytecode matches, only the
  explorer's displayed source is stale. Etherscan V2 rejects re-verification of verified
  contracts (`hardhat verify --force` cannot refresh it); it ages out at the next redeploy.
- **Hardhat-verify config gotcha:** `etherscan.apiKey` as an object (`{ <network>: key }`)
  forces hardhat-verify onto the retired Etherscan V1 endpoint ("You are using a
  deprecated V1 endpoint"). Keep it a single string, `apiKey: process.env.ETHERSCAN_API_KEY`
  — V2 multichain covers every Etherscan chain; Blockscout chains go through `customChains`.

---

## Unified Full/Lite codebase — reference

One codebase serves both deployment modes (merged to `master` at `f8d2d45`): **Full**
(Base — KSU token, locking, loyalty) and **Lite** (no token/locking/loyalty, same
signature-gated deposits). Lite behaviour is override-based, in:
- `src/core/KsuPriceLite.sol`
- `src/core/ProtocolFeeManagerLite.sol`
- `src/core/UserLoyaltyRewardsLite.sol`
- `src/core/UserManagerLite.sol`
- `src/locking/KSULockingLite.sol`

Deployment flags are env-gated (`DEPLOY_MOCK_USDC`, `DEPLOY_SYSTEM_VARIABLES_TESTABLE`,
`DEPLOY_UPDATES`, `VERIFY_SOURCE`); `scripts/dev/**` refuse to run off a local network
(`requireLocalNetwork()`); `scripts/_modules/usdc.ts` prevents minting on non-mock USDC.

### Production Script Environment Variables
| Script | Required Env Vars |
|--------|-------------------|
| `doClearing.ts` | `LENDING_POOL_ADDRESS`, `NUMBER_OF_TRANCHES`, `DRAW_AMOUNT`, `TARGET_EPOCH_NUMBER` |
| `updateDesiredDrawAmount.ts` | `LENDING_POOL_ADDRESS`, `DESIRED_DRAW_AMOUNT` |
| `repayOwedFunds.ts` | `LENDING_POOL_ADDRESS`, `REPAY_AMOUNT` |
| `grantLendingPoolRole.ts` | `LENDING_POOL_ADDRESS`, `ACCOUNT_ADDRESS` |
| `stopLendingPool.ts` | `LENDING_POOL_ADDRESS` |
| `admin/transferAllProxyAdminOwnership.ts` | `NEW_PROXY_ADMIN_OWNER` |
| `admin/validateDeployment.ts` | (optional) `AUTO_VERIFY=true` |

### Chain Configuration
Chain-specific settings are defined in `scripts/_config/chains.ts` and used by `deploy.ts`:
- **Supported chains**: localhost, hardhat, base-sepolia, base, xdc, plume
- **Extensible**: Add new chains to `CHAIN_CONFIGS` or use env variables for unknown chains
- **Per-chain config**: `deploymentMode`, `wrappedNativeAddress`, `usdcAddress`, `nexeraIdSigner`, `protocolFeeReceiver`, multisig addresses, `isTestnet`
- **Env overrides**: `WRAPPED_NATIVE_ADDRESS`, `USDC_ADDRESS`, `NEXERA_ID_SIGNER` override chain defaults (but NOT `deploymentMode` or `protocolFeeReceiver` which are chain-specific only)

### Contract Verification (Etherscan V2)
Uses Etherscan V2 Multichain API - **single `ETHERSCAN_API_KEY`** works for 100+ chains including:
- Ethereum, Base, XDC, Arbitrum, Optimism, Polygon, etc.
- Full list: https://docs.etherscan.io/supported-chains

**Blockscout explorers** (e.g., Plume):
- Use Blockscout API (free, no API key required)
- Explorer: https://explorer.plume.org
- API: https://explorer.plume.org/api/v2
- `PLUME_SCAN_API_KEY` is optional (empty string works)

To deploy to a new EVM chain:
1. Add chain config to `scripts/_config/chains.ts` (including `deploymentMode` and `protocolFeeReceiver`)
2. Add network to `hardhat.config.ts`
3. Run: `npx hardhat --network <network> deploy`

### Smoke Tests

Post-deployment validation scripts in `scripts/smokeTests/`:

```bash
# Complete deployment validation (recommended - auto-discovers pools!)
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts

# Basic role and ownership validation (quick check, no pools)
npx hardhat --network base run scripts/smokeTests/validateRolesAndOwnership.ts

# Manual pool specification (optional override)
LENDING_POOL_ADDRESSES=0xpool1,0xpool2 \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

**What gets validated:**

*Global checks (validateDeploymentComplete.ts):*
- ✅ ProxyAdmin ownership (must be Kasu multisig, not deployer)
- ✅ Beacon ownership (must be Kasu multisig, not deployer)
- ✅ ROLE_KASU_ADMIN (Kasu multisig has it, deployer does not)
- ✅ ROLE_LENDING_POOL_FACTORY (LendingPoolFactory contract)
- ✅ ROLE_LENDING_POOL_CREATOR (pool admin multisig)
- ✅ ROLE_PROTOCOL_FEE_CLAIMER (validates expected address from chain config)
- ✅ protocolFeeReceiver (prints the address, validates not deployer)

*Pool-specific checks (validatePoolRoles.ts):*
- ✅ ROLE_POOL_ADMIN (pool admin multisig, per pool)
- ✅ ROLE_POOL_CLEARING_MANAGER (pool admin multisig, per pool)
- ✅ ROLE_POOL_MANAGER (pool manager multisig, per pool)
- ✅ ROLE_POOL_FUNDS_MANAGER (pool manager multisig, per pool)

*Tenderly simulation (Base only - requires credentials):*
- ✅ Simulates `lendingPoolManager.createPool()` with LENDING_POOL_CREATOR role
- ✅ Verifies pool creation works before on-chain execution
- ✅ No gas cost, no on-chain state changes
- ⚠️  Skipped on XDC/Plume (not supported by Tenderly)
- ⚠️  Skipped if Tenderly credentials not configured

**Multisig Addresses:**

*Kasu Multisig (Proxy ownership & ROLE_KASU_ADMIN):*
- Base: `0xC3128d734563E0d034d3ea177129657408C09D35`
- Plume: `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`
- XDC: `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`

*Pool Manager Multisig (ROLE_POOL_MANAGER, ROLE_POOL_FUNDS_MANAGER):*
- Base: `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2`
- Plume: `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe`
- XDC: `0x21567eA21b14BEd14657e9725C2FE11C7be942B1`

*Pool Admin Multisig (ROLE_LENDING_POOL_CREATOR, ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER):*
- Base: `0x7adf999af5E0617257014C94888cf98c4584E5E9`
- Plume: `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF`
- XDC: `0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112`

*InvoiceMate Multisig (ROLE_POOL_MANAGER, ROLE_POOL_FUNDS_MANAGER, ROLE_POOL_CLEARING_MANAGER
+ draw recipient on the Base Payment Finance pool `0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE`
only — note the pool manager Safe `0x39905d…` holds **no** role on that pool):*
- Base: `0x156aea25b5C62210Ea42F0A08791253688705eC9` (Safe v1.4.1, 2-of-3)
- Base (old, retired 2026-09-22): `0x793DAEec8293A6869b42cc56988b6780f458d4f3` — 3-of-3 with a
  lost signer key, permanently unable to transact. Stranded USDC swept and roles migrated via
  `scripts/recovery/safe-batches/base-invoicemate-safe-migration.json`. Never grant it a role
  again, and never set it as a draw recipient.

Configure via `scripts/_config/chains.ts` or env variables (`KASU_MULTISIG`, `POOL_MANAGER_MULTISIG`, `POOL_ADMIN_MULTISIG`).

See `scripts/smokeTests/README.md` for full documentation.

### Plume Deployment Status

Plume (Lite) is **retired** — wound down and fully drained (last activity 2026-01-07);
it survives only as frozen since-inception history. Addresses stay in
`.openzeppelin/plume-addresses.json`; do not target it with upgrades, role changes or
fee rollouts.
### XDC AUDD Deployment Status

XDC AUDD is a Lite deployment (deployed Feb 2026) with epoch timing aligned to Base (Thursday 06:00 UTC).
Epochs are weekly. Epoch 0 start on-chain: `1717653600` (Thu, 6 Jun 2024 06:00:00 UTC) — same anchor as Base.

**Status: FINALIZED (Apr 13, 2026)**
- ✅ Deployment contracts deployed and initialized (deploy_1.ts)
- ✅ Role grants: ROLE_KASU_ADMIN, ROLE_LENDING_POOL_CREATOR, ROLE_PROTOCOL_FEE_CLAIMER (deploy_2.ts)
- ✅ All 7 source-mismatched implementations upgraded (Apr 9, 2026) and verified on xdcscan
- ✅ 3 pools created + configured by Apxium multisig
- ✅ Pool-specific roles configured on all pools (ROLE_POOL_MANAGER + ROLE_POOL_FUNDS_MANAGER granted to pool admin multisig 0x880Aa2...)
- ✅ deploy_3.ts executed (Apr 13, 2026): 16 ProxyAdmin + 3 Beacon ownerships transferred to Kasu multisig, ROLE_KASU_ADMIN revoked from deployer
- ✅ Smoke tests: 25/25 global checks passing

### XDC USDC Deployment Status

Second Lite deployment on XDC using USDC (`0xfa2958cb79b0491cc627c1557f441ef849ca8eb1`) instead of AUDD.
Network name: `xdc-usdc`. Shares chain ID 50, same multisigs, separate contract stack.

**Status (Apr 13, 2026): FINALIZED on mainnet.** 19 contracts deployed, initialized, roles granted, ownership transferred. All impls verified on xdcscan.

**Epoch anchor off-by-one (discovered 2026-05-14 — REALIGNED since):** SystemVariables was initialized with `_initialEpochStartTimestamp = 1718258400` (Thu 13 Jun 2024 06:00 UTC) instead of the canonical Kasu anchor `1717653600` (Thu 6 Jun 2024 06:00 UTC) used by Base and XDC AUDD — `chains.ts` set both `xdc` and `xdc-usdc` to `1718258400` in commit `6aa0f91` and `finishXdcUsdcInit.ts` propagated it on-chain. Corrected on-chain with a one-shot `SystemVariablesEpochAlignmentMigration` impl and a Kasu-multisig Safe batch (both retired from the repo 2026-09-24 after execution; the backup is outside git); all three live deployments now return the same `currentEpochNumber()` (117 on each, read on-chain 2026-09-03). Before any redeploy, check that `chains.ts` carries `1717653600` for both XDC entries.

**Completed:**
- ✅ deploy_1.ts — 19 contracts deployed + initialized; SystemVariables epoch-aligned to AUDD via one-time migration impl dance (since removed from the repo)
- ✅ deploy_2.ts — ROLE_KASU_ADMIN, ROLE_LENDING_POOL_CREATOR, ROLE_PROTOCOL_FEE_CLAIMER granted to multisigs
- ✅ All 19 production impls verified on xdcscan (one orphaned SystemVariablesMigration impl remains verified on-chain, no proxy points to it)
- ✅ Addresses saved to `.openzeppelin/xdc-usdc-addresses.json`
- ✅ deploy_3.ts executed (Apr 13, 2026): 16 ProxyAdmin + 3 Beacon ownerships transferred to Kasu multisig, ROLE_KASU_ADMIN revoked from deployer
- ✅ Smoke tests: 25/25 global checks passing

**Post-deploy completed:**
- ✅ Apxium multisig created 4 pools via ROLE_LENDING_POOL_CREATOR (`0x0c80…3948c0`, `0x4B5f…40013`, `0xAc3B…AB5F`, `0xEabB…CeC5`)
- ✅ Goldsky subgraph `kasu-xdc-usdc/v1.0.0` deployed — `https://api.goldsky.com/api/public/project_cmgzlpxm300765np2a19421om/subgraphs/kasu-xdc-usdc/v1.0.0/gn`
- ✅ kasu-sdk updated and published: `@kasufinance/kasu-sdk@2.2.1`
- ✅ Gitbook docs updated (kasu-gitbook-techdocs); user-facing kasu-gitbook-kasu-finance is chain-agnostic, no updates needed

**Epoch alignment (historical):**
`SystemVariables.initialize()` validates `initialEpochStartTimestamp` must be within `[now - 1 week, now]`, rejecting alignment to any anchor older than one week. Both XDC AUDD (Feb 2026) and XDC USDC (Apr 2026) had to bootstrap with the canonical Kasu anchor `1717653600` (Thu 6 Jun 2024 06:00 UTC, matching Base), so each used a one-shot migration-impl flow: upgrade the SV proxy to a stripped-check `SystemVariablesMigration` impl, atomically `upgradeAndCall(initialize(...))` with the past anchor, then upgrade back to the production SV impl (storage preserved). AUDD's run successfully wrote `1717653600`; USDC's run wrote `1718258400` due to a `chains.ts` config bug (see "⚠️ Epoch anchor off-by-one week" above), leaving USDC one epoch number behind Base + AUDD until the realignment above. Both legacy migration impls are verified-but-orphaned on xdcscan. The `SystemVariablesMigration.sol` contract and `scripts/recovery/finishXdcUsdcInit*.ts` scripts were removed from the repo after first use, but are still in git history at commit `6aa0f91`. The USDC realignment used a different one-shot impl (`SystemVariablesEpochAlignmentMigration`, ROLE_KASU_ADMIN-gated setter, no re-`initialize()`) because the existing proxy is already initialized.

**⚠️ Known gotcha:** `upgrades.erc1967.getImplementationAddress()` and proxy view calls immediately after `upgrades.upgradeProxy` can return stale data on XDC RPC (load-balanced, some nodes lag). Always verify via raw storage read of the EIP-1967 impl slot (`0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`) for critical state checks.

**Deploy sequence (for reference / redeploy scenarios):**
```bash
npx hardhat --network xdc-usdc run scripts/deploy_1.ts
# If SV initialize reverts due to past-timestamp check, restore a migration-impl flow
# from git history (scripts/recovery/finishXdcUsdcInit*.ts were deleted after use).
npx hardhat --network xdc-usdc run scripts/deploy_2.ts
# deploy_3.ts DEFERRED (see "Finalizing XDC")
npx hardhat --network xdc-usdc run scripts/smokeTests/validateDeploymentComplete.ts
AUTO_VERIFY=true ETHERSCAN_API_KEY=... npx hardhat --network xdc-usdc run scripts/admin/validateDeployment.ts
```

**Post-deploy:** Pools created by Apxium multisig (`0x880Aa2d6...`) via ROLE_LENDING_POOL_CREATOR.

**Addresses:** `.openzeppelin/xdc-usdc-addresses.json`.

**XDC RPC:** **Never use `https://rpc.xdc.org`** — it is unreliable and took the
backend's chain-50 poller down on 2026-08-24. Primary is
`https://rpc.primenumbers.xyz/`. The backend runs an ordered failover list
(`primenumbers, ankr, xdcrpc.com, rpc.xinfin.network` via a comma-separated
`CHAIN_50_RPC_URL`); scripts here take a single URL and default to primenumbers,
overridable with `XDC_RPC_URL`.

### Finalizing XDC (COMPLETED Apr 13, 2026)

deploy_3.ts executed on both `xdc` and `xdc-usdc`. All ProxyAdmin + Beacon ownerships transferred to Kasu multisig (`0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`). Deployer's ROLE_KASU_ADMIN revoked on both. Smoke tests verified: 25/25 global checks on both networks.

### ⚠️ Apxium Multisig Template Bug (XDC AUDD historical)

When the Apxium pool admin multisig set up the XDC AUDD pools, **3 transactions for granting `ROLE_POOL_MANAGER` / `ROLE_POOL_FUNDS_MANAGER` called a wrong target address** (an EOA `0x7923837dc93d897e12696e0f4fd50b51fbacf693` instead of KasuController). The calls succeeded silently as no-ops. That address is the **Plume** KasuController — they reused the Plume template on XDC. The roles were subsequently granted to the pool admin Safe `0x880Aa2…` only; the pool manager Safe `0x21567e…` never received any pool role on AUDD (verified on-chain 2026-09-02, all 3 pools), unlike Base / xdc-usdc / Plume where it holds `ROLE_POOL_MANAGER` + `ROLE_POOL_FUNDS_MANAGER`. First symptom: the `repayOwedFunds` Safe batch proposed from `0x21567e…` (nonce 8, 2026-09-02) reverts with `AccessControlUnauthorizedAccount`. Fix batch (6 grants, executed by `0x880Aa2…`): `scripts/recovery/safe-batches/xdc-audd-grant-pool-manager-roles.json` (see the README there). **Warn Apxium before they configure any new pools to double-check their Safe Transaction Builder template targets that chain's KasuController.**

### `release-candidate` — the next upgrade cycle

`master` mirrors what is deployed on-chain. Contract changes that are ready but not yet
deployed are collected on the long-lived **`release-candidate`** branch, and ship together in
the next impl upgrade cycle. After deployment, `release-candidate` merges into `master`.
So `validateDeployment.ts` should be run against `master`, not `release-candidate`.

Queued for the next cycle:
- **Clearing dust-spill guard** (`AcceptedRequestsExecution`, PendingPool impl, all chains).
  Once a request is fully accepted, deposit execution no longer touches its burned dNFT a
  second time with a zero amount. Regression test: `ClearingDustSpillRevertTest`.

### Deployment & Upgrade Workflow

Every deployment or upgrade MUST follow this sequence:

1. **Dry-run on Anvil fork** before touching mainnet:
```bash
anvil --fork-url https://rpc.primenumbers.xyz/ --chain-id 50 --port 8546
XDC_RPC_URL=http://127.0.0.1:8546 npx hardhat --network xdc run scripts/upgrade/upgradeXdcImplementations.ts
```

2. **Deploy/upgrade on mainnet**

3. **Validate bytecode** — confirm 0 source mismatches:
```bash
ETHERSCAN_API_KEY=... npx hardhat --network <network> run scripts/admin/validateDeployment.ts
```

4. **Verify on Etherscan** — auto-verify implementations:
```bash
AUTO_VERIFY=true ETHERSCAN_API_KEY=... npx hardhat --network <network> run scripts/admin/validateDeployment.ts
```
For contracts with constructor args that fail auto-verify, verify manually:
```bash
npx hardhat verify --network <network> <impl_address> <constructor_arg1> <constructor_arg2> ...
# If the contract name is ambiguous (e.g. ProtocolFeeManagerLite extends FeeManager), add:
#   --contract src/path/ContractName.sol:ContractName
```

**Etherscan V2 + hardhat-verify 2.x known issue (XDC and other V2 chains):**
The plugin submits source code successfully but the subsequent status check fails with
`Missing chainid parameter`. This is a false negative — the verification actually succeeds.
Always confirm verification via the Etherscan V2 API after submission:
```bash
curl -s "https://api.etherscan.io/v2/api?chainid=<CHAIN_ID>&module=contract&action=getsourcecode&address=<ADDRESS>&apikey=<KEY>" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); r=d['result'][0]; print(r.get('ContractName','NOT VERIFIED') if d['status']=='1' and r.get('ContractName') else 'NOT VERIFIED')"
```

**Constructor args for implementation contracts:** These are immutable values baked in at deploy time.
Find them in `deploy_1.ts` or the upgrade script that deployed the implementation. Common pattern:
- `LendingPoolManager`: 5 args (fixedTermDeposit, usdc, controller, weth, swapper)
- `ProtocolFeeManagerLite`: 5 args (usdc, systemVariables, controller, ksuLocking, lendingPoolManager)
- `KasuPoolExternalTVL`: 1 arg (controller)
All addresses come from the chain's `.openzeppelin/<network>-addresses.json` and `chains.ts` config.

5. **Smoke tests** — validate roles, ownership, configuration:
```bash
npx hardhat --network <network> run scripts/smokeTests/validateDeploymentComplete.ts
```

### Tenderly Simulations

Transaction simulations using Tenderly API for testing on deployed networks without on-chain execution.

**Supported chains**: Only Base (Tenderly doesn't support XDC or Plume). The `tenderlySupported` flag in `chains.ts` controls this.

**Integrated into smoke tests**: The `validateDeploymentComplete.ts` script automatically runs Tenderly simulations on supported chains if credentials are configured.

```bash
# Run smoke tests (includes Tenderly simulation on Base only)
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

**Prerequisites (optional - for Tenderly simulations only):**
```bash
export TENDERLY_ACCESS_KEY=your_access_key
export TENDERLY_ACCOUNT_ID=your_username_or_org
export TENDERLY_PROJECT_SLUG=your_project
```

**What gets simulated:**
- ✅ `lendingPoolManager.createPool()` with LENDING_POOL_CREATOR role
- ✅ Verifies role-based access control works correctly
- ✅ No gas cost, no on-chain state changes
- ✅ Skipped automatically on unsupported chains (XDC, Plume)

See `scripts/tenderly/README.md` for full documentation.

### Important Constraints
- Lite must still support signature-gated (KYC/KYB) deposits
- Full must remain behaviorally identical to `master` for upgradability

### Security Audits

- Before auditing any Solidity contracts, refer to 'skills/SECURITY_AUDIT.md' for detailed audit guidelines and output format.
