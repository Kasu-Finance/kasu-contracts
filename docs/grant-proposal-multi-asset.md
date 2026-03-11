# Multi-Asset Support for Kasu Protocol

## Executive Summary

Kasu is an RWA (Real World Asset) private credit lending platform connecting DeFi investors with lending entities for business loan origination. The protocol currently operates with a single stablecoin (USDC) as its base asset across all deployments.

This proposal covers two phases of work to expand the protocol's asset support:

- **Phase 1**: Flexible stable asset — enable each chain deployment to use its own native stablecoin (e.g., AUDD on XDC, USDC on Base), with full frontend and smart contract adaptability.
- **Phase 2**: Multi-asset pools — allow a single lending pool to accept deposits in multiple stablecoins simultaneously, with independent per-asset accounting and clearing.

## Problem Statement

As Kasu expands to new blockchains, the need to support region-specific stablecoins becomes critical. For example, the XDC Network deployment targets the Australian market, where AUDD (Australian Dollar stablecoin) is the preferred asset. Today, the protocol's smart contracts are asset-agnostic by design, but the frontend and deployment tooling assume USDC everywhere — from UI labels and currency symbols to CSV exports and user-facing educational content.

Looking ahead, institutional borrowers increasingly need to accept capital in multiple currencies within a single pool. A corporate lending pool on Base may want to accept both USDC and AUDD deposits, clearing each independently while sharing the same governance, tranche structure, and interest rates.

## Phase 1: Flexible Stable Asset

### Goal

Enable each chain deployment to operate with any ERC20 stablecoin as its base asset, with the frontend dynamically adapting to show the correct token name, symbol, and currency formatting.

### Smart Contract Changes

The smart contracts are already asset-agnostic — the underlying asset is injected via constructor and all operations use it generically. The changes needed are:

- **Deployment configuration**: Update chain configuration to point to the correct stablecoin address per chain (e.g., AUDD on XDC)
- **Implementation upgrades**: For existing deployments switching assets, deploy new implementation contracts compiled with the new asset address and upgrade via beacon/proxy pattern
- **Naming conventions**: Rename USDC-specific configuration fields and helpers to generic "stable asset" terminology for clarity

No Solidity code changes are required — the contracts work with any 6-decimal ERC20 token out of the box.

### Frontend Changes

The frontend currently has ~280 hardcoded references to USDC/USD across configuration, components, localization strings, and utility functions. The work includes:

**Dynamic token resolution**
- Read the stablecoin's name, symbol, and decimals from on-chain data at application startup
- Cache the token metadata and refresh when the user switches chains
- Provide a React hook (`useStablecoinConfig`) that components use instead of hardcoded values

**UI component updates**
- Replace hardcoded `'USDC'` symbol props across ~30 component files with dynamic values
- Update currency formatting utilities to support multiple currencies (USD `$`, AUD `A$`, etc.)
- Add chain-aware token icon selection

**Localization**
- Introduce parameterized locale strings with `{stablecoin}` placeholders (currently ~114 hardcoded "USDC" references in user-facing text)
- Update approval messages, educational content, and descriptions

**Data exports**
- Make CSV export column headers and value formatting dynamic based on the active chain's stablecoin

### Estimated Effort: ~3 weeks

| Task | Effort |
|------|--------|
| On-chain token metadata reading and caching | 2 days |
| Stablecoin config hook and provider | 2 days |
| Component updates (30 files) | 3 days |
| Locale string parameterization (114 refs) | 2 days |
| Currency formatting utilities | 2 days |
| CSV export updates | 1 day |
| Deployment config and implementation upgrades | 2 days |
| Testing and validation | 2 days |

## Phase 2: Multi-Asset Pools

### Goal

Allow a single lending pool to accept deposits in multiple stablecoins simultaneously. Each asset operates through its own independent "lane" within the pool — separate deposit tracking, clearing runs, tranche balances, and owed amounts — while sharing the pool's governance, tranche structure, interest rates, and clearing schedule.

### Why Per-Asset Lanes

Different stablecoins have different values (1 AUDD is not equal to 1 USDC). The protocol cannot simply sum deposits across currencies. Each asset must be cleared independently with its own inputs, and users must receive back the same asset they deposited.

The chosen architecture avoids oracle dependencies and FX risk by keeping each asset's accounting fully independent. The existing clearing algorithm — a pure function that takes aggregate amounts in a single denomination — runs unchanged, simply called once per asset with that asset's inputs.

### Smart Contract Changes

**Core contracts** (LendingPool, PendingPool, LendingPoolTranche):
- New per-asset storage mappings for LP balances, tranche shares, pending deposits, and owed amounts
- New methods (`acceptDepositInAsset`, `drawFundsInAsset`, `repayOwedFundsInAsset`, etc.) alongside existing ones
- The base asset (USDC) continues using existing ERC20/ERC4626 infrastructure — fully backwards compatible

**Orchestration contracts** (ClearingCoordinator, LendingPoolManager, FeeManager):
- Per-asset clearing orchestration — same 5-step process, run independently per asset
- Asset registry on each pool (add/remove allowed assets)
- Per-asset fee collection and protocol fee claiming

**Key design decisions**:
- Base asset uses existing ERC20 LP token and ERC4626 tranche vaults — zero impact on existing depositors
- Additional assets use storage mappings (no new token contracts needed, since tranche shares are non-transferable)
- All existing public method signatures remain unchanged — new methods are added alongside
- Clearing algorithm itself requires no changes — called per-asset with per-asset inputs
- Interest rates are shared across assets (pool-level config), applied independently to each asset's balances
- No oracle or FX conversion needed

**Upgrade strategy**:
- All changes are additive — new storage appended, new methods added
- Beacon proxy upgrades apply to all pool instances atomically
- Pre-upgrade deposits continue working identically (default `address(0)` = base asset)
- Rollback is safe — new storage is simply ignored by previous implementations

### Frontend Changes

**Pool deposit flow**:
- Asset selector for pools with multiple allowed assets
- Per-asset balance display and deposit/withdrawal amounts
- Per-asset tranche share tracking in portfolio views

**Clearing and admin views**:
- Per-asset clearing status and configuration
- Per-asset draw amount settings
- Independent owed amount tracking per asset

**Data model**:
- Extend pool data to include per-asset balances and metadata
- Per-asset transaction history and CSV exports

### Estimated Effort: ~5 weeks

| Task | Effort |
|------|--------|
| Interfaces and events | 2 days |
| LendingPoolTranche per-asset shares | 4 days |
| LendingPool per-asset accounting | 6 days |
| PendingPool per-asset tracking | 6 days |
| FeeManager per-asset fees | 2 days |
| ClearingCoordinator per-asset clearing | 3 days |
| LendingPoolManager entry points and asset registry | 3 days |
| Unit and integration tests | 8 days |
| Frontend: per-asset deposit/withdrawal flow | 4 days |
| Frontend: portfolio and admin views | 3 days |
| Deployment scripts and validation | 3 days |

## Timeline

| Phase | Duration | Milestone |
|-------|----------|-----------|
| Phase 1: Flexible stable asset | Weeks 1-3 | XDC deployment with AUDD, dynamic frontend |
| Phase 2: Multi-asset pools | Weeks 4-8 | Per-asset deposits, clearing, and withdrawals |
| **Total** | **~8 weeks** | |

## Backwards Compatibility

Both phases maintain full backwards compatibility:

- All existing public method signatures remain unchanged
- Pre-upgrade deposits, withdrawals, and LP tokens continue working identically
- Pools without additional assets configured behave exactly as they do today
- The upgrade is purely additive — no existing storage is modified or reordered
- Rollback is supported by pointing beacons/proxies back to previous implementations

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Storage layout collision on upgrade | Validated via hardhat-upgrades plugin and Tenderly simulation before deployment |
| Per-asset clearing gas costs | Batch sizes are already configurable; per-asset clearing runs independently |
| Tranche share precision for additional assets | Same decimal offset (12) as base asset; extensive testing with edge cases |
| Frontend token metadata availability | Graceful fallback to configured defaults if on-chain read fails |

## Deliverables

1. Updated smart contracts with per-asset support (auditable Solidity code)
2. Deployment and upgrade scripts for all supported chains
3. Frontend with dynamic stablecoin support and per-asset pool views
4. Comprehensive test suite (unit, integration, and upgrade simulation tests)
5. Storage layout validation and Tenderly simulation scripts
6. Documentation covering architecture, migration, and operational procedures
