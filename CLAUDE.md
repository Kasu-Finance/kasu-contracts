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

# 3. Production deployment
DEPLOYMENT_MODE=full npx hardhat --network base deploy   # Full deployment with KSU token
DEPLOYMENT_MODE=lite npx hardhat --network plume deploy  # Lite version without token functionality
```

Environment files are loaded from `scripts/_env/.{network}.env` (e.g., `.base.env`, `.plume.env`).
See `scripts/_env/.env.example` for all available options.

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
DEPLOYMENT_MODE=full npx hardhat --network base run scripts/admin/validateDeployment.ts
DEPLOYMENT_MODE=lite npx hardhat --network plume run scripts/admin/validateDeployment.ts

# Auto-verify unverified contracts that match source
DEPLOYMENT_MODE=full AUTO_VERIFY=true npx hardhat --network base run scripts/admin/validateDeployment.ts

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
| `admin/validateDeployment.ts` | `DEPLOYMENT_MODE` (full/lite), (optional) `AUTO_VERIFY=true` |

### Chain Configuration
Chain-specific addresses are defined in `scripts/_config/chains.ts` and used by `deploy.ts`:
- **Supported chains**: localhost, hardhat, base-sepolia, base, xdc, plume
- **Extensible**: Add new chains to `CHAIN_CONFIGS` or use env variables for unknown chains
- **Per-chain config**: `wrappedNativeAddress`, `usdcAddress`, `nexeraIdSigner`, `isTestnet`
- **Env overrides**: `WRAPPED_NATIVE_ADDRESS`, `USDC_ADDRESS`, `NEXERA_ID_SIGNER` override chain defaults

### Contract Verification (Etherscan V2)
Uses Etherscan V2 Multichain API - **single `ETHERSCAN_API_KEY`** works for 100+ chains including:
- Ethereum, Base, XDC, Arbitrum, Optimism, Polygon, etc.
- Full list: https://docs.etherscan.io/supported-chains

Non-Etherscan explorers (e.g., Plume) need separate API keys (`PLUME_SCAN_API_KEY`).

To deploy to a new EVM chain:
1. Add chain config to `scripts/_config/chains.ts` OR set env variables
2. Add network to `hardhat.config.ts`
3. Run: `DEPLOYMENT_MODE=lite npx hardhat --network <network> deploy`

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
- ✅ ROLE_PROTOCOL_FEE_CLAIMER (prints who has it)
- ✅ protocolFeeReceiver (prints the address, validates not deployer)

*Pool-specific checks (validatePoolRoles.ts):*
- ✅ ROLE_POOL_ADMIN (pool admin multisig, per pool)
- ✅ ROLE_POOL_CLEARING_MANAGER (pool admin multisig, per pool)
- ✅ ROLE_POOL_MANAGER (pool manager multisig, per pool)
- ✅ ROLE_POOL_FUNDS_MANAGER (pool manager multisig, per pool)

**Multisig Addresses:**

*Kasu Multisig (Proxy ownership & ROLE_KASU_ADMIN):*
- Base: `0xC3128d734563E0d034d3ea177129657408C09D35`
- Plume: `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`
- XDC: `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`

*Pool Manager Multisig (ROLE_POOL_MANAGER, ROLE_POOL_FUNDS_MANAGER):*
- Base: `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2`
- Plume: `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe`
- XDC: Not set yet

*Pool Admin Multisig (ROLE_LENDING_POOL_CREATOR, ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER):*
- Base: `0x7adf999af5E0617257014C94888cf98c4584E5E9`
- Plume: `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF`
- XDC: Not set yet

Configure via `scripts/_config/chains.ts` or env variables (`KASU_MULTISIG`, `POOL_MANAGER_MULTISIG`, `POOL_ADMIN_MULTISIG`).

See `scripts/smokeTests/README.md` for full documentation.

### Open TODOs
- Simulate `lendingPoolManager.createPool` can be called in both Full and Lite deployments by the LENDING_POOL_CREATOR role account
- Test the NEXERA endpoint and signature verification in both Full and Lite deployments
- Validate pool-specific roles on individual lending pools after pool creation (global roles are now validated by smoke tests)

### Important Constraints
- Lite must still support KYC/KYB (Nexera) gated deposits
- Full must remain behaviorally identical to `master` for upgradability
