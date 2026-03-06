# Multi-Asset Architecture

## Current Architecture (Single Asset)

```
User USDC ──> LendingPoolManager ──> PendingPool ──[clearing]──> LendingPool ──> drawRecipient
                                          |                           |
                                     Deposit NFT              LP Token (ERC20)
                                     (assetAmount)            Tranche Shares (ERC4626)
                                                              Interest accrual
                                                              Fees -> FeeManager
```

All contracts share a single `_underlyingAsset` (USDC) set as an `immutable` in `AssetFunctionsBase`. Every amount in the system — LP tokens, tranche shares, pending deposits, owed amounts, fees — is denominated in this single asset.

## Proposed Architecture (Per-Asset Sub-Pools)

```
User USDC ──> LendingPoolManager ──> PendingPool ──[clearing USDC]──> LendingPool ──> drawRecipient
User AUDD ──> LendingPoolManager ──> PendingPool ──[clearing AUDD]──> LendingPool ──> drawRecipient
                                          |                               |
                                    Deposit NFT                   Per-asset LP balances
                                    (assetAmount + asset)         Per-asset tranche shares
                                                                  Per-asset interest
                                                                  Per-asset owed amounts
                                                                  Per-asset fees
```

### Core Concept: Per-Asset Lanes

Each pool operates as a **multi-currency pool** where each asset runs through its own independent "lane":

- **USDC lane**: Uses existing `_underlyingAsset` immutable, existing ERC20 LP token, existing ERC4626 tranche vaults. Completely unchanged from current behavior.
- **AUDD lane** (and any additional asset): Uses new storage mappings for LP balances, tranche shares, owed amounts, etc. Same interest rates, same tranches, same clearing algorithm — but separate amounts.

The pool's **governance is shared** across all asset lanes:
- Same pool admin, pool manager
- Same tranche structure (senior/junior)
- Same interest rates per tranche
- Same clearing schedule and epoch timing
- Same KYC/allowlist requirements

But each asset lane has **independent accounting**:
- Separate pending deposit totals
- Separate clearing runs
- Separate LP token balances (base = ERC20, additional = mappings)
- Separate tranche share balances (base = ERC4626, additional = mappings)
- Separate draw amounts and owed amounts
- Separate fee accumulation

### Why Per-Asset Lanes (Not Conversion)

Assets like USDC and AUDD have different values (1 AUDD != 1 USDC). The alternatives were:

| Approach | Issue |
|----------|-------|
| Convert to base on deposit (oracle) | FX risk, oracle dependency, complex withdrawal math |
| Treat as equivalent (1:1) | Incorrect accounting, arbitrage opportunity |
| **Independent per-asset tracking** | Clean, no FX risk, no oracle needed |

### Asset Configuration

Each pool has a set of allowed assets configured after pool creation:

```
Pool "Corporate Loans A"
├── Base asset: USDC (always enabled, immutable)
├── Additional assets:
│   ├── AUDD (enabled)
│   └── (future: more assets)
```

Asset configuration is managed via `LendingPoolManager` (or a new `AssetRegistry` contract) by the pool admin. Adding/removing additional assets does not affect existing deposits.

## Design Decisions

### 1. Base Asset Uses Existing ERC20/ERC4626

The base asset (USDC) continues to use:
- `LendingPool` ERC20 token for LP balances
- `LendingPoolTranche` ERC4626 vault for tranche shares

This ensures 100% backwards compatibility. Existing depositors, scripts, and integrations are unaffected.

### 2. Additional Assets Use Storage Mappings

Additional assets use `mapping(address asset => ...)` for:
- LP balances (instead of ERC20 `balanceOf`)
- Tranche shares (instead of ERC4626 `balanceOf`)
- Pending deposit amounts
- Owed amounts

This avoids deploying new ERC20/ERC4626 contracts per asset. Since tranche shares are non-transferable (`onlyAllowed` modifier) and LP tokens are internal-only, there is no composability loss.

### 3. Clearing Runs Per-Asset

The clearing algorithm (`AcceptedRequestsCalculation`) is a pure function that takes:
- Total pending deposit amount
- Total pending withdrawal amount
- Per-tranche deposit amounts
- Pool balance (excess, owed)
- Draw amount

All inputs are amounts in a single denomination. By feeding it per-asset inputs, the same algorithm runs independently for each asset. No changes to the algorithm itself.

### 4. Withdrawal Returns Same Asset as Deposit

Users always receive back the same asset they deposited. This is tracked via the deposit NFT's asset field. No cross-asset withdrawal is supported in the initial implementation.

### 5. Borrower Draws and Repays Per-Asset

The borrower (draw recipient) specifies which asset to draw during clearing. Repayments are made in the same asset. The pool tracks `userOwedAmount` and `feesOwedAmount` per asset.

### 6. Fees Per-Asset

Fees are collected in the asset that generated them. Options for distribution:
- **Per-asset fee accumulation**: FeeManager tracks fees per asset, protocol fee claimer claims each separately.
- **Base-asset only (deferred)**: Convert fees to base asset before emission to KSULocking. Requires swap infrastructure.

Recommended initial approach: per-asset fee accumulation with per-asset protocol fee claiming. KSULocking ecosystem fees only from base asset (simplest). Additional asset ecosystem fees accumulated in FeeManager until a swap mechanism is added.

### 7. Interest Rates Are Shared Across Assets

A pool's tranche interest rates apply equally to all asset lanes. For example, if the senior tranche rate is 8% APY, both USDC and AUDD senior deposits earn 8% in their respective currencies.

This is a pool-level configuration decision. If different rates per asset are needed in the future, it can be added as an override layer.

## Asset Flow: Deposit

```
1. User calls LendingPoolManager.requestDepositInAsset(lendingPool, tranche, asset, amount, ...)
2. LendingPoolManager validates asset is allowed for pool
3. LendingPoolManager transfers `asset` from user to itself
4. LendingPoolManager approves PendingPool to spend `asset`
5. PendingPool.requestDepositInAsset(user, tranche, asset, amount, ftdConfigId)
   - Transfers `asset` from LendingPoolManager to PendingPool
   - Creates/updates deposit NFT with asset field set
   - Updates per-asset pending deposit tracking
6. Deposit NFT minted to user (same ERC721 system)
```

For base asset, the existing `requestDeposit()` is used — unchanged.

## Asset Flow: Clearing

```
For each asset in pool's asset list:
  Step 1: Apply interest (per-asset LP balances)
  Step 2: Calculate priorities (per-NFT, asset-aware aggregation)
  Step 3: Calculate accepted amounts (per-asset, same algorithm)
  Step 4: Execute accepted requests
    - Accept deposit: transfer correct asset, update per-asset LP balance, per-asset tranche shares
    - Reject deposit: return correct asset to user
    - Accept withdrawal: redeem per-asset tranche shares, transfer correct asset to user
  Step 5: Draw funds (per-asset draw amount, transfer correct asset to borrower)
  End: Pay owed fees (per-asset)
```

## Asset Flow: Withdrawal

```
1. User calls LendingPoolManager.requestWithdrawalInAsset(lendingPool, tranche, asset, shares)
   - `asset` must match the asset the user deposited in
   - `shares` are per-asset tranche shares
2. PendingPool creates withdrawal NFT with asset field
3. During clearing, LendingPool redeems per-asset shares, transfers correct asset to user
```

For base asset, the existing `requestWithdrawal()` is used. Base-asset tranche shares are in the ERC4626 vault as before.

## Asset Flow: Draw and Repay

```
Draw:
1. ClearingCoordinator calls LendingPool.drawFundsInAsset(amount, asset)
2. LendingPool transfers `asset` to drawRecipient
3. userOwedAmountPerAsset[asset] += amount

Repay:
1. Pool manager calls LendingPoolManager.repayOwedFundsInAsset(lendingPool, asset, amount, repaymentAddress)
2. LendingPool receives `asset`, reduces userOwedAmountPerAsset[asset]
3. Fees paid per-asset to FeeManager
```

For base asset, existing `drawFunds()` and `repayOwedFunds()` continue to work.
