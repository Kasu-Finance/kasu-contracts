# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kasu is an RWA (Real World Asset) private credit lending platform built on Solidity. It connects DeFi investors with lending entities for business loan origination. The platform uses permissioned lending pools with epoch-based clearing, KYC requirements via NexeraID, and a KSU token-based loyalty system.

## Build & Test Commands

```bash
# Install dependencies
forge install          # Foundry dependencies
npm install           # JS dependencies for deployment scripts

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

Configured networks: localhost, base-sepolia, base (mainnet), xdc

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

### Production Script Environment Variables
| Script | Required Env Vars |
|--------|-------------------|
| `doClearing.ts` | `LENDING_POOL_ADDRESS`, `NUMBER_OF_TRANCHES`, `DRAW_AMOUNT`, `TARGET_EPOCH_NUMBER` |
| `updateDesiredDrawAmount.ts` | `LENDING_POOL_ADDRESS`, `DESIRED_DRAW_AMOUNT` |
| `repayOwedFunds.ts` | `LENDING_POOL_ADDRESS`, `REPAY_AMOUNT` |
| `grantLendingPoolRole.ts` | `LENDING_POOL_ADDRESS`, `ACCOUNT_ADDRESS` |
| `stopLendingPool.ts` | `LENDING_POOL_ADDRESS` |

### Chain Configuration
Chain-specific addresses are defined in `scripts/_config/chains.ts` and used by `deploy.ts`:
- **Supported chains**: localhost, hardhat, base-sepolia, base, xdc, xdc-apothem, plume
- **Extensible**: Add new chains to `CHAIN_CONFIGS` or use env variables for unknown chains
- **Per-chain config**: `wrappedNativeAddress`, `usdcAddress`, `nexeraIdSigner`, `explorerApiUrl`, `isTestnet`
- **Env overrides**: `WRAPPED_NATIVE_ADDRESS`, `USDC_ADDRESS`, `NEXERA_ID_SIGNER` override chain defaults

To deploy to a new EVM chain:
1. Add chain config to `scripts/_config/chains.ts` OR set env variables
2. Add network to `hardhat.config.ts`
3. Run: `DEPLOYMENT_MODE=lite npx hardhat --network <network> deploy`

### Open TODOs
- Add smoke test scripts for deployment validation

### Important Constraints
- Lite must still support KYC/KYB (Nexera) gated deposits
- Full must remain behaviorally identical to `master` for upgradability
