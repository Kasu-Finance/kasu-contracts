# Effort Estimate & Implementation Plan

## Summary

| Phase | Effort | Description |
|-------|--------|-------------|
| Phase 1: Core contracts | ~3 weeks | PendingPool, LendingPool, LendingPoolTranche changes |
| Phase 2: Orchestration | ~1.5 weeks | ClearingCoordinator, LendingPoolManager, FeeManager |
| Phase 3: Testing | ~2 weeks | Unit tests, integration tests |
| Phase 4: Deployment | ~1 week | Scripts, validation, multi-chain |
| **Total** | **~7-8 weeks** | |

## Phase 1: Core Contracts (~3 weeks)

### 1.1 PendingPool (5-6 days)

The most impacted contract. Changes span deposit tracking, clearing aggregation, and request execution.

| Task | Effort | Details |
|------|--------|---------|
| New storage variables | 0.5 days | `_depositAsset`, `_withdrawalAsset`, per-asset pending totals |
| `requestDepositInAsset()` | 1 day | New method mirroring `requestDeposit()` with asset tracking |
| `requestWithdrawalInAsset()` | 0.5 days | New method with asset tracking |
| Modified `_acceptDepositRequest()` | 1 day | Asset-aware approve/transfer routing |
| Modified `_returnDepositRequest()` | 0.5 days | Asset-aware refund |
| Modified `cancelDepositRequest()` | 0.5 days | Routes through modified `_returnDepositRequest` |
| Per-asset ClearingData storage | 0.5 days | `_clearingDataPerEpochPerAsset` mapping |
| Modified priority calculation | 1 day | Per-asset aggregation in `calculatePendingRequestsPriorityBatch()` |
| Modified execution | 0.5 days | Per-asset ClearingData lookup in `executeAcceptedRequestsBatch()` |

**Dependencies**: IPendingPool interface updates, IClearingStepsData struct awareness.

### 1.2 LendingPool (5-6 days)

Per-asset LP balance tracking, interest accrual, draw/repay flows.

| Task | Effort | Details |
|------|--------|---------|
| New storage variables | 0.5 days | Per-asset supply, tranche balances, owed amounts, first loss capital |
| `acceptDepositInAsset()` | 1 day | Transfer asset, update per-asset balances, call tranche |
| `acceptWithdrawalInAsset()` | 1 day | Redeem per-asset shares, transfer asset to user |
| `drawFundsInAsset()` | 0.5 days | Transfer asset to draw recipient |
| `repayOwedFundsInAsset()` | 0.5 days | Receive asset, update owed amounts |
| `applyInterestsPerAsset()` | 1 day | Per-asset interest calculation and tranche balance updates |
| `depositFirstLossCapitalInAsset()` | 0.5 days | Per-asset first loss |
| `forceImmediateWithdrawalInAsset()` | 0.5 days | Per-asset forced withdrawal |
| `availableFundsPerAsset()` | 0.5 days | Per-asset available funds view |
| `payOwedFeesPerAsset()` | 0.5 days | Per-asset fee payment at clearing end |

**Dependencies**: ILendingPool interface updates, LendingPoolTranche per-asset methods.

### 1.3 LendingPoolTranche (3-4 days)

Per-asset share tracking parallel to ERC4626.

| Task | Effort | Details |
|------|--------|---------|
| New storage variables | 0.5 days | Per-asset shares, active shares, total assets |
| `depositInAsset()` | 1 day | Per-asset share minting with correct ratio calculation |
| `redeemInAsset()` | 1 day | Per-asset share burning and asset conversion |
| `removeUserActiveSharesPerAsset()` | 0.5 days | Per-asset active share tracking |
| `applyInterestPerAsset()` | 0.5 days | Update per-asset total assets (changes share ratio) |
| View functions | 0.5 days | `convertToAssetsPerAsset()`, `userActiveAssetsPerAsset()` |

**Dependencies**: Called by LendingPool per-asset methods.

### 1.4 Interfaces & Events (1-2 days)

| Task | Effort | Details |
|------|--------|---------|
| ILendingPool additions | 0.5 days | New method signatures |
| IPendingPool additions | 0.5 days | New method signatures |
| ILendingPoolTranche additions | 0.5 days | New method signatures |
| IFeeManager additions | 0.25 days | `emitFeesInAsset`, `claimProtocolFeesInAsset` |
| IClearingCoordinator additions | 0.25 days | `doClearingForAsset` |
| New events | 0.5 days | Per-asset versions of existing events |

## Phase 2: Orchestration (~1.5 weeks)

### 2.1 ClearingCoordinator (2-3 days)

| Task | Effort | Details |
|------|--------|---------|
| `doClearingForAsset()` | 1.5 days | Per-asset clearing orchestration (5 steps) |
| Per-asset clearing status tracking | 0.5 days | New storage for per-asset clearing state |
| Per-asset clearing config | 0.5 days | Per-asset draw amounts |

### 2.2 LendingPoolManager (2-3 days)

| Task | Effort | Details |
|------|--------|---------|
| `requestDepositInAsset()` | 0.5 days | New entry point |
| `requestDepositInAssetWithKyc()` | 0.5 days | KYC variant |
| `repayOwedFundsInAsset()` | 0.5 days | Per-asset repay |
| `depositFirstLossCapitalInAsset()` | 0.25 days | Per-asset first loss |
| `forceImmediateWithdrawalInAsset()` | 0.25 days | Per-asset forced withdrawal |
| Asset registry (add/remove/query) | 0.5 days | `addPoolAdditionalAsset()`, `removePoolAdditionalAsset()` |
| `doClearingForAsset()` routing | 0.5 days | Entry point for per-asset clearing |

### 2.3 FeeManager (1-2 days)

| Task | Effort | Details |
|------|--------|---------|
| `emitFeesInAsset()` | 0.5 days | Per-asset fee collection |
| `claimProtocolFeesInAsset()` | 0.5 days | Per-asset fee claiming |
| ProtocolFeeManagerLite variant | 0.5 days | Lite version if needed |

### 2.4 FixedTermDeposit (2-3 days)

| Task | Effort | Details |
|------|--------|---------|
| Per-asset deposit tracking | 1 day | Track which asset each FTD is in |
| Modified lock/unlock | 1 day | Use per-asset tranche shares |
| Fixed interest per asset | 1 day | Apply fixed rate to per-asset balances |

## Phase 3: Testing (~2 weeks)

### 3.1 Unit Tests (8-10 days)

| Test Area | Effort | Details |
|-----------|--------|---------|
| PendingPool per-asset deposits | 1.5 days | Deposit, cancel, accept, reject in additional asset |
| LendingPool per-asset accounting | 1.5 days | Accept deposit, withdrawal, interest, owed tracking |
| LendingPoolTranche per-asset shares | 1 day | Share minting, redemption, ratio calculation |
| Per-asset clearing flow | 2 days | Full 5-step clearing with mixed base + additional assets |
| FeeManager per-asset fees | 0.5 days | Fee collection and claiming |
| LendingPoolManager entry points | 1 day | All new methods with validation |
| FixedTermDeposit per-asset | 1 day | Lock, unlock, interest with additional asset |
| Edge cases | 1 day | Zero balances, pool with no additional assets, pre-upgrade NFTs |
| Backwards compatibility | 1 day | Verify existing tests pass unchanged |

### 3.2 Integration Tests (2-3 days)

| Test Area | Effort | Details |
|-----------|--------|---------|
| Full lifecycle: deposit → clear → withdraw per asset | 1 day | End-to-end flow |
| Mixed asset pool: USDC + AUDD deposits, independent clearing | 1 day | Both assets in same pool |
| Upgrade simulation: pre-upgrade deposits + post-upgrade additional asset deposits | 0.5 days | Backwards compat |
| Multi-tranche with multi-asset | 0.5 days | Senior/junior with both USDC and AUDD |

## Phase 4: Deployment (~1 week)

### 4.1 Deployment Scripts (2-3 days)

| Task | Effort | Details |
|------|--------|---------|
| `deployMultiAssetImplementations.ts` | 1 day | Deploy new implementations |
| `generateMultiAssetUpgradeBatch.ts` | 0.5 days | Gnosis Safe TX batch |
| `addPoolAdditionalAsset.ts` | 0.5 days | Configure pools |
| Modified `doClearing.ts` | 0.5 days | Per-asset clearing support |
| Modified `repayOwedFunds.ts` | 0.5 days | Per-asset repay support |

### 4.2 Validation & Smoke Tests (2 days)

| Task | Effort | Details |
|------|--------|---------|
| Storage layout validation script | 0.5 days | Verify no storage collision |
| Extended smoke tests | 1 day | Per-asset role checks, balance checks |
| Tenderly simulation | 0.5 days | Simulate upgrade + first per-asset deposit |

### 4.3 Multi-Chain Deployment (2-3 days)

| Chain | Effort | Notes |
|-------|--------|-------|
| Base (Full) | 1 day | Primary deployment + validation |
| Plume (Lite) | 0.5 days | Lite variant implementations |
| XDC (Lite) | 0.5 days | Same as Plume |

## Risks & Mitigations

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Storage layout collision on beacon upgrade | Critical | Low | Validate with `hardhat-upgrades` plugin, Tenderly simulation |
| Per-asset clearing gas exceeds block limit | Medium | Low | Batch sizes already configurable, per-asset clearing is independent |
| Tranche share ratio precision loss for additional assets | Medium | Medium | Use same `_decimalsOffset()` (12) as base asset ERC4626, extensive testing |
| ClearingData storage bloat (per-asset × per-epoch) | Low | Medium | ClearingData is overwritten per epoch, old epochs are not accessed |
| FixedTermDeposit complexity with per-asset | Medium | Medium | Can defer FTD multi-asset to Phase 2 if needed |
| Priority calculation single-pass vs multi-pass | Low | Low | Single-pass with per-asset aggregation is more gas efficient |

## Implementation Dependencies

```
Phase 1.4 (Interfaces)
  ├──> Phase 1.1 (PendingPool)
  ├──> Phase 1.2 (LendingPool)
  │      └──> Phase 1.3 (LendingPoolTranche) — LendingPool calls Tranche
  └──> Phase 2.3 (FeeManager) — LendingPool calls FeeManager

Phase 1.1 + 1.2 + 1.3
  └──> Phase 2.1 (ClearingCoordinator) — orchestrates per-asset clearing

Phase 2.1 + 2.3
  └──> Phase 2.2 (LendingPoolManager) — entry points that route to all contracts

Phase 1.2
  └──> Phase 2.4 (FixedTermDeposit) — uses per-asset tranche shares

All Phase 1 + 2
  └──> Phase 3 (Testing)
  └──> Phase 4 (Deployment)
```

## Suggested Implementation Order

1. Interfaces & events (Phase 1.4)
2. LendingPoolTranche per-asset shares (Phase 1.3)
3. LendingPool per-asset accounting (Phase 1.2) — depends on 1.3
4. PendingPool per-asset tracking (Phase 1.1) — depends on 1.2
5. FeeManager per-asset (Phase 2.3)
6. ClearingCoordinator per-asset (Phase 2.1) — depends on 1.1, 1.2
7. LendingPoolManager entry points (Phase 2.2) — depends on all above
8. FixedTermDeposit per-asset (Phase 2.4) — can be parallel with 2.1/2.2
9. Unit tests (Phase 3.1) — continuous, but bulk after Phase 2
10. Integration tests (Phase 3.2)
11. Deployment scripts & validation (Phase 4)

## What Can Be Deferred

If time is constrained, these can be deferred to a follow-up:

| Feature | Impact of Deferral |
|---------|-------------------|
| FixedTermDeposit per-asset | FTD only works with base asset. Additional asset deposits can't use FTD. |
| Per-asset ecosystem fees to KSULocking | Additional asset fees go to protocol only. KSULocking stays base-asset. |
| Per-asset loss tracking (LendingPoolTrancheLoss) | Losses apply to base asset only. Additional asset positions unaffected by impairment. |
| Multi-decimal support | All additional assets must be 6 decimals. Can be extended later. |
| `DepositSwap` for additional assets | Users can't swap other tokens to AUDD on deposit. Direct AUDD transfer only. |
