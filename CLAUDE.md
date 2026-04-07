# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kasu is an RWA (Real World Asset) private credit lending platform built on Solidity. It connects DeFi investors with lending entities for business loan origination. The platform uses permissioned lending pools with epoch-based clearing, KYC requirements via NexeraID, and a KSU token-based loyalty system.

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

## KYC/KYB Verification (Nexera/Compilot)

Kasu uses [Compilot](https://compilot.ai) (formerly NexeraID) for KYC/KYB signature gating. The flow:

```
Frontend → Compilot API → returns signature → Frontend sends TX → KasuAllowList verifies signature
```

**How it works:**
1. Frontend calls Compilot API (`https://api.compilot.ai/customer-tx-auth-signature`) with chainId, contract, function, user
2. If user is KYC'd, Compilot signs the request with their private key
3. Frontend appends signature + blockExpiration to TX calldata
4. `KasuAllowList.verifyUserKyc()` calls `_verifyTxAuthData()` which validates the signature on-chain

**Key contracts:**
- `KasuAllowList.sol` - Extends `TxAuthDataVerifierUpgradeable` from vendored NexeraID contracts
- `vendor/nexera/BaseTxAuthDataVerifier.sol` - Core signature verification logic
- `vendor/nexera/TxAuthDataVerifierUpgradeable.sol` - Upgradeable wrapper

**NEXERA_ID_SIGNER:**
- This is the `NexeraIDSignerManager` contract address (not an EOA)
- Compilot deploys this per-chain; it manages the actual signing key
- Current address for supported chains: `0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0`
- If Compilot rotates their signing key, they update the manager - no action needed from Kasu
- For new chains: request Compilot to deploy `NexeraIDSignerManager` and provide the address

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

## Current WIP: Unified Full/Lite Codebase (branch: `release-candidate`)

### Goal
Single unified codebase supporting:
- **Full deployment**: Identical behavior to `master` (KSU token, locking, loyalty system)
- **Lite deployment**: No Kasu token/locking/loyalty, but same KYC/KYB/Nexera allowlisting and deposits
- Preserve upgradability for existing Base deployment
- Maintain all ExternalTVL behavior

### Lite Contract Implementations
Override-based behavior changes in:
- `src/core/KsuPriceLite.sol`
- `src/core/ProtocolFeeManagerLite.sol`
- `src/core/UserLoyaltyRewardsLite.sol`
- `src/core/UserManagerLite.sol`
- `src/locking/KSULockingLite.sol`

### Work Completed
- Lite implementations for all token-dependent contracts
- FixedTermDeposit bug fix (`userTrancheSharesAfter = trancheShares`)
- Plume OpenZeppelin files for future upgrades (`.openzeppelin/plume-addresses.json`, `.openzeppelin/unknown-98866.json`)
- GitHub workflows run tests on push/PR (`.github/workflows/test.yml`)
- Updated `diagrams/flows.puml` with KasuAllowList, SystemVariables, FixedTermDeposit, clearing steps
- Scripts reorganized: dev-only scripts moved to `scripts/dev/**`
- USDC helper to prevent minting on non-mock USDC (`scripts/_modules/usdc.ts`)
- Deployment uses env-gated flags (DEPLOY_MOCK_USDC, DEPLOY_SYSTEM_VARIABLES_TESTABLE, DEPLOY_UPDATES, VERIFY_SOURCE)
- **Validated Full vs master**: No regressions - changes are visibility modifiers (`private`→`internal`, `+virtual`) for Lite inheritance + FixedTermDeposit bug fix
- **Production scripts parameterized**: All hardcoded addresses replaced with env variables (`scripts/_utils/env.ts`)
- **Dev script network guard**: All `scripts/dev/**` now require local network via `requireLocalNetwork()`
- **Migrated to npm dependencies**: OpenZeppelin via npm (v5.0.2), NexeraID vendored (2 files), removed 3 git submodules
- **Etherscan V2 multichain**: Single `ETHERSCAN_API_KEY` for all supported chains (Base, XDC, etc.)

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

### Base Mainnet Upgrade Status
Validated via `validateDeployment.ts` - contracts modified from `master` that need upgrading:

| Contract | Change Type | Status on Base |
|----------|-------------|----------------|
| `UserManager.sol` | Visibility changes (`private`→`internal`, `+virtual`) | **Needs upgrade** |
| `FeeManager.sol` | Visibility changes (`private`→`internal`, `+virtual`) | **Needs upgrade** |
| `FixedTermDeposit.sol` | Bug fix (`userTrancheSharesAfter = trancheShares`) | **Needs upgrade** |
| `LendingPoolManager.sol` | Visibility changes (`public virtual`) | Already deployed with changes |

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

Configure via `scripts/_config/chains.ts` or env variables (`KASU_MULTISIG`, `POOL_MANAGER_MULTISIG`, `POOL_ADMIN_MULTISIG`).

See `scripts/smokeTests/README.md` for full documentation.

### Plume Deployment Status

Plume has a Lite deployment with new implementations deployed, awaiting multisig execution.

**Current State (Feb 9, 2026):**
- ✅ All ProxyAdmin ownership (Kasu multisig)
- ✅ All Beacon ownership (Kasu multisig)
- ✅ ROLE_KASU_ADMIN granted to Kasu multisig
- ✅ ROLE_LENDING_POOL_FACTORY granted to LendingPoolFactory
- ✅ ROLE_LENDING_POOL_CREATOR granted to pool admin multisig
- ✅ ROLE_PROTOCOL_FEE_CLAIMER granted correctly
- ✅ All pool-specific roles configured for 3 pools
- ❌ Old admin `0x0e7e...483` still has DEFAULT_ADMIN_ROLE (needs revoke)
- ❌ 7 contracts need upgrade to match source code

**New Implementations Deployed:**
| Contract | New Implementation |
|----------|-------------------|
| KSULockingLite | `0x6BABEa605337b3C6D0106d83864d73706971355f` |
| KsuPriceLite | `0xe81D1C0E031da0E357928ED19aA1EbF6A2f5C904` |
| SystemVariables | `0x990bCF7f23d58Fa121209ABaF812836b651c82bC` |
| FixedTermDeposit | `0x7fF469f8c5fba92A9051B8D28794CBb891760e81` |
| UserLoyaltyRewardsLite | `0xC7c808e0C9fd7F97EA23b7eA21d94104564C6aC0` |
| UserManagerLite | `0x666b589933965bF8B378eD973f0404b6cae0eb52` |
| ProtocolFeeManagerLite | `0x161931FC6AFb8195B7516E4D129AcA437c15CA38` |

**Action Required - Execute via Gnosis Safe:**

Upload `scripts/multisig/plume-upgrade-all.json` to Gnosis Safe Transaction Builder:
- 7 upgrade transactions (ProxyAdmin.upgradeAndCall)
- 1 revoke transaction (remove old admin DEFAULT_ADMIN_ROLE)

**Verify after execution:**
```bash
npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts
npx hardhat --network plume run scripts/admin/validateDeployment.ts
```

### XDC Deployment Status

XDC has a Lite deployment (deployed Feb 2026) with epoch timing aligned to Base.

**Epoch Timing (aligned Feb 6, 2026):**
- ✅ Epochs now transition on Thursday 06:00 UTC (same as Base)
- ✅ Initial epoch start: Thu, 29 Jan 2026 06:00:00 UTC
- ✅ Epoch 1 preserved (existing deposit safe)

**Pending Tasks:**
- ❌ ProxyAdmin ownership: Still with deployer, needs transfer to Kasu multisig
- ❌ Beacon ownership: Still with deployer, needs transfer to Kasu multisig
- ❌ ROLE_KASU_ADMIN: Deployer still has it, needs revocation
- ✅ ROLE_KASU_ADMIN: Kasu multisig has it
- ✅ ROLE_LENDING_POOL_FACTORY: Granted to LendingPoolFactory
- ✅ ROLE_LENDING_POOL_CREATOR: Granted to pool admin multisig
- ✅ ROLE_PROTOCOL_FEE_CLAIMER: Granted correctly
- ✅ Pool-specific roles: Configured for all 3 pools

**Action Required:**

1. **Transfer ProxyAdmin ownership** (16 contracts):
```bash
NEW_PROXY_ADMIN_OWNER=0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D \
  npx hardhat --network xdc run scripts/admin/transferAllProxyAdminOwnership.ts
```

2. **Revoke deployer admin role** (via Kasu multisig):
```solidity
kasuController.revokeRole(0x00, 0x2e202f7A4D5F670D76921aA44B94940bAa87d8F9)
```

3. **Verify**:
```bash
npx hardhat --network xdc run scripts/smokeTests/validateDeploymentComplete.ts
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

### Testing Checklist

- ✅ Smoke tests validated on Base (Full deployment)
- ✅ Smoke tests validated on Plume (Lite deployment)
  - Blockscout API works without API key
  - Revealed role configuration issues (needs upgrade and role grants)
- ✅ Smoke tests validated on XDC (Lite deployment)
  - Epoch timing aligned to Thursday 06:00 UTC
  - Pending: ownership transfer and deployer role revocation
- ✅ Tenderly simulation integrated into smoke tests
- ⏸️  Nexera/Compilot endpoint testing (manual testing only - not automated)

### Important Constraints
- Lite must still support KYC/KYB (Nexera) gated deposits
- Full must remain behaviorally identical to `master` for upgradability

### Security Audits

- Before auditing any Solidity contracts, refer to 'skills/SECURITY_AUDIT.md' for detailed audit guidelines and output format.
