# Per-Asset Clearing

## Current Clearing Flow (Single Asset)

The clearing process runs once per pool per epoch in 5 steps:

```
Step 1: Apply interests        → LendingPool.applyInterests(epoch)
Step 2: Priority calculation   → PendingPool.calculatePendingRequestsPriorityBatch(epoch, batchSize)
Step 3: Accepted amounts       → PendingPool.calculateAndSaveAcceptedRequests(config, balance, epoch)
Step 4: Execute requests       → PendingPool.executeAcceptedRequestsBatch(epoch, batchSize)
Step 5: Draw funds             → LendingPool.drawFunds(drawAmount)
End:    Pay owed fees           → LendingPool.payOwedFees()
```

All amounts throughout this process are in a single denomination (base asset).

## Why Clearing Must Be Per-Asset

The clearing algorithm (`AcceptedRequestsCalculation`) takes these inputs:

```solidity
struct ClearingInput {
    PendingDeposits pendingDeposits;       // totalDepositAmount, per-tranche, per-priority
    PendingWithdrawals pendingWithdrawals;  // totalWithdrawalsAmount, per-priority
    ClearingConfiguration config;           // drawAmount, trancheRatios, excess percentages
    LendingPoolBalance balance;             // excess, owed
}
```

These are all **plain number sums**. If a pool has pending deposits of 1000 USDC and 1000 AUDD, you cannot sum them to get 2000 — the assets have different values. Each asset must be cleared independently with its own inputs.

## Per-Asset Clearing Flow

For each pool, clearing runs **once for base asset** (existing flow, unchanged) and **once per additional asset**:

```
Base asset clearing:  doClearing(pool, epoch, ...)         — existing method, unchanged
AUDD clearing:        doClearingForAsset(pool, epoch, AUDD, ...)  — new method
```

Each per-asset clearing follows the same 5-step process:

### Step 1: Apply Interest (Per-Asset)

```
Base:  LendingPool.applyInterests(epoch)           — existing, uses ERC20 balanceOf(tranche)
AUDD:  LendingPool.applyInterestsPerAsset(epoch, AUDD)  — new, uses trancheBalancePerAsset[AUDD][tranche]
```

Interest rate is the same (pool-level config). Interest amount differs because balances differ:

```
base interest  = trancheBalance_USDC  * interestRate / INTEREST_RATE_FULL_PERCENT
AUDD interest  = trancheBalance_AUDD  * interestRate / INTEREST_RATE_FULL_PERCENT
```

Interest is denominated in the same asset (AUDD interest is in AUDD, USDC interest is in USDC).

### Step 2: Priority Calculation (Per-Asset)

**`PendingRequestsPriorityCalculation.calculatePendingRequestsPriorityBatch()`** currently iterates all NFTs and aggregates into a single `ClearingData`:

```solidity
// Current: line 128-131 — aggregates ALL deposits
clearingData.pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
```

**Change**: Per-asset aggregation. When processing each NFT, check its asset and aggregate into the correct per-asset ClearingData:

```solidity
address asset = _depositAsset[userRequestNftId]; // address(0) = base
ClearingData storage clearingData = _clearingDataForAsset(targetEpoch, asset);
clearingData.pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
clearingData.pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
clearingData.pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][priority] += depositNftDetails.assetAmount;
```

Similarly for withdrawals:

```solidity
address asset = _withdrawalAsset[userRequestNftId];
ClearingData storage clearingData = _clearingDataForAsset(targetEpoch, asset);
// ... aggregate withdrawal shares for this asset
```

**Key**: Priority levels (loyalty) are per-user, not per-asset. A user with loyalty level 3 has level 3 for both their USDC and AUDD deposits.

### Step 3: Calculate Accepted Amounts (Per-Asset)

`AcceptedRequestsCalculation.calculateAcceptedRequests()` is a **pure function** — no changes needed. It's called with per-asset inputs:

```solidity
// For base asset:
calculateAcceptedRequests(ClearingInput{
    pendingDeposits: clearingData_USDC.pendingDeposits,
    pendingWithdrawals: clearingData_USDC.pendingWithdrawals,
    config: clearingConfig,   // same config
    balance: LendingPoolBalance(availableFunds_USDC, userOwedAmount_USDC)
});

// For AUDD:
calculateAcceptedRequests(ClearingInput{
    pendingDeposits: clearingData_AUDD.pendingDeposits,
    pendingWithdrawals: clearingData_AUDD.pendingWithdrawals,
    config: clearingConfig_AUDD,  // may have different drawAmount
    balance: LendingPoolBalance(availableFundsPerAsset(AUDD), userOwedAmountPerAsset[AUDD])
});
```

The algorithm determines how many AUDD deposits are accepted, how many AUDD withdrawals are accepted, based on the AUDD-denominated pool balance and draw requirements — all in AUDD terms.

### Step 4: Execute Accepted Requests (Per-Asset)

`AcceptedRequestsExecution.executeAcceptedRequestsBatch()` iterates NFTs and calls accept/reject. The modified `_acceptDepositRequest` and `_acceptWithdrawalRequest` (see CONTRACT_CHANGES.md) route to the correct asset-specific methods.

**Critical**: The execution must use per-asset ClearingData for accepted amounts:

```solidity
// Current (line 106-108 in AcceptedRequestsExecution.sol):
uint256 totalAccepted = clearingData.tranchePriorityDepositsAccepted[trancheIndex][priority][k];

// New: use per-asset clearing data
address asset = _depositAsset[dNftID];
ClearingData storage assetClearingData = _clearingDataForAsset(targetEpoch, asset);
uint256 totalAccepted = assetClearingData.tranchePriorityDepositsAccepted[trancheIndex][priority][k];
```

The proportional acceptance calculation stays the same:
```
userAccepted = totalAccepted * userAmount / totalRequested
```
But now `totalAccepted` and `totalRequested` are both in the same asset's denomination.

### Step 5: Draw Funds (Per-Asset)

```
Base:  LendingPool.drawFunds(drawAmount)                    — existing
AUDD:  LendingPool.drawFundsInAsset(drawAmount_AUDD, AUDD)  — new
```

The borrower specifies how much of each asset to draw. These are set in the per-asset clearing configuration.

### End: Pay Owed Fees (Per-Asset)

```
Base:  LendingPool.payOwedFees()                           — existing
AUDD:  LendingPool.payOwedFeesPerAsset(AUDD)               — new
```

## ClearingData Storage

### Current

```solidity
// In ClearingSteps.sol
mapping(uint256 epoch => ClearingData) private _clearingDataPerEpoch;
```

### New (Per-Asset)

```solidity
// In ClearingSteps.sol (PendingPool inherits this)
mapping(uint256 epoch => mapping(address asset => ClearingData)) private _clearingDataPerEpochPerAsset;

// Base asset (address(0)) uses the existing _clearingDataPerEpoch for backwards compatibility.
// Additional assets use _clearingDataPerEpochPerAsset.
```

## Clearing Configuration Per-Asset

Each asset can have a different `drawAmount` in the clearing configuration. The pool admin sets:

```
Base clearing config:  drawAmount = 50,000 (USDC)
AUDD clearing config:  drawAmount = 30,000 (AUDD)
```

Other config fields (tranche ratios, excess percentages) are shared across assets — they're structural properties of the pool, not currency-specific.

If different excess percentages per asset are needed in the future, the clearing config can be extended.

## Clearing Script Changes

The `doClearing.ts` script currently calls `doClearing()` once per pool. With multi-asset:

```typescript
// Clear base asset (existing)
await lendingPoolManager.doClearing(
    poolAddress, targetEpoch, ftdBatchSize,
    priorityBatchSize, acceptBatchSize,
    clearingConfig, isConfigOverridden
);

// Clear each additional asset
const additionalAssets = await lendingPoolManager.poolAdditionalAssets(poolAddress);
for (const asset of additionalAssets) {
    // Check if there are pending deposits/withdrawals for this asset
    const pendingAmount = await pendingPool.pendingDepositAmountForCurrentEpochPerAsset(asset);
    if (pendingAmount > 0 || hasOwedAmount) {
        await lendingPoolManager.doClearingForAsset(
            poolAddress, targetEpoch, asset,
            ftdBatchSize, priorityBatchSize, acceptBatchSize,
            clearingConfigForAsset, isConfigOverridden
        );
    }
}
```

## Execution Order

Per-asset clearings are independent — they can run in any order. However, for gas efficiency:

1. Run base asset clearing first (it's the primary asset)
2. Run additional asset clearings in order

If a pool has no pending deposits/withdrawals in a specific asset, that asset's clearing can be skipped entirely (only interest + fee payment needed).

## Gas Considerations

- Priority calculation (Step 2) currently iterates all NFTs in a single pass. With per-asset aggregation, it still iterates once but writes to per-asset storage — slightly more gas per NFT due to additional mapping lookups.
- Execution (Step 4) also iterates once. The per-NFT asset check adds ~200 gas per NFT (one SLOAD for `_depositAsset[dNftID]`).
- Running clearing per-asset means additional transactions for each additional asset. If a pool has 2 assets and 100 pending NFTs split 80/20, the clearing overhead is ~20% more transactions.
