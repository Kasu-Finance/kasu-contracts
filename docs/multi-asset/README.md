# Multi-Asset Support: Per-Asset Sub-Pool Architecture

## Overview

This document describes the design for adding multi-asset support to the Kasu protocol. The approach adds "additional assets" (e.g., AUDD — Australian Dollar stablecoin) alongside the existing "base asset" (USDC), with fully independent per-asset accounting throughout the protocol.

### Key Principles

1. **Per-asset independence**: Each asset has its own LP balance, tranche shares, interest accrual, clearing, draw, repay, and fee flow. Assets are never mixed or converted.
2. **Backwards compatibility**: All existing public method signatures remain unchanged. Existing base-asset flows work identically. Pre-upgrade deposits continue to function.
3. **Upgradeability**: All changes are additive storage (appended to existing contracts). No storage reordering. Compatible with existing TransparentUpgradeableProxy and BeaconProxy deployments.
4. **No oracle dependency**: Since assets are tracked independently, no FX conversion or price feeds are needed.

### Documents

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | High-level architecture, asset flow diagrams, design decisions |
| [CONTRACT_CHANGES.md](./CONTRACT_CHANGES.md) | Detailed per-contract changes with storage layouts, new methods, modified methods |
| [CLEARING.md](./CLEARING.md) | How per-asset clearing works with the existing algorithm |
| [MIGRATION.md](./MIGRATION.md) | Upgrade path, backwards compatibility, deployment steps |
| [EFFORT.md](./EFFORT.md) | Effort breakdown, implementation phases, risks |

### Scope

- **In scope**: Base asset (USDC) + additional assets (AUDD, potentially others) with independent per-asset flows for deposits, clearing, interest, draw, repay, withdrawals, and fees.
- **Out of scope**: Cross-asset swaps/conversions, oracle-based normalization, multi-decimal support (all assets assumed 6 decimals for initial implementation).
- **Deferred**: Multi-decimal support can be added later by parameterizing decimal assumptions.
