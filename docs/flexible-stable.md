# Flexible Stable Asset Naming

## Context

The Kasu protocol currently names its base stable asset as "USDC" throughout the codebase — in configuration, scripts, environment variables, deployment files, tests, and contract comments. However, the protocol is asset-agnostic by design: the `_underlyingAsset` is injected via constructor/initializer and all contracts operate on it generically via `AssetFunctionsBase`.

As we expand to new chains (e.g., XDC with AUDD — Australian Dollar stablecoin), the USDC naming becomes misleading. This document outlines the changes needed to make the naming chain/asset-agnostic.

## Current State

### Solidity Contracts (src/)

**No functional changes needed.** All 23 USDC references in `src/` are comments only. The contracts are fully asset-agnostic:

- `AssetFunctionsBase.sol` — `IERC20 internal immutable _underlyingAsset` (no USDC reference)
- `LendingPool.sol` — `decimals() = 6` (works for any 6-decimal token)
- `LendingPoolTranche.sol` — `_decimalsOffset() = 12` (correct for 6-decimal underlying)
- `LendingPoolTrancheLoss.sol` — `minimumAssetAmountLeftAfterLoss = 10 * 1e6` (means "10 units of stable")
- `UserManager.sol` — `_rKSUInUSDC()` with `1e12` (correct for 6-decimal, but only active in full mode)
- `UserLoyaltyRewards.sol` — `1e12` multiplier (correct for 6-decimal, only active in full mode)

### Chain Configuration (`scripts/_config/chains.ts`)

| Field | Current Name | Used By |
|-------|-------------|---------|
| `usdcAddress` | USDC address per chain | `deploy_1.ts`, env override `USDC_ADDRESS` |

Current XDC config (line 136): `usdcAddress: '0xfa2958cb79b0491cc627c1557f441ef849ca8eb1'` — this is the USDC address on XDC. To deploy with AUDD, this must be changed to the AUDD token address.

### Environment Variables (`.env.example`)

| Variable | Purpose |
|----------|---------|
| `DEPLOY_MOCK_USDC` | Deploy a mock token for local testing |
| `USDC_ADDRESS` | Override chain config stable asset address |
| `USDC_IS_MOCK` | Whether the deployed stable is a mock |

### Deployment Script (`scripts/deploy_1.ts`)

- Line 68: `deployMockUSDC` flag
- Line 86: `let usdcAddress = chainConfig.usdcAddress`
- Line 103-108: Log messages say "usdc"
- Line 136-148: Deploys `MockUSDC` and stores as key `"USDC"` in deployment JSON
- Lines 261, 271, 317, 329, 344, 384: Passes `usdcAddress` to contract constructors/initializers

### Helper Module (`scripts/_modules/usdc.ts`)

| Function | Purpose |
|----------|---------|
| `getUsdcContract()` | Reads `addresses.USDC.address` from deployment file |
| `isMockUsdc()` | Checks if deployed stable is MockUSDC |
| `fundUsdcUsers()` | Mints mock tokens to test users |

### Deployment Address Files (`.openzeppelin/`)

All chains store the stable asset under the key `"USDC"`:
- `.openzeppelin/xdc-addresses.json` line 4: `"USDC": { "address": "0xfa..." }`
- Base and Plume deployment files use the same `"USDC"` key

### Tests

| File | References |
|------|-----------|
| `test/shared/MockUSDC.sol` | Mock ERC20 named "MockUSDC" with 6 decimals |
| `test/unit/_utils/BaseTestUtils.sol` | Creates MockUSDC, passes to all contracts |
| Various test files | Variable names like `usdc`, `mockUsdc` |

## Proposed Changes

### Phase 1: Configuration & Scripts (Do Now)

#### 1.1 Rename `usdcAddress` in `chains.ts`

```typescript
// Before
usdcAddress: '0xfa2958cb79b0491cc627c1557f441ef849ca8eb1',

// After
stableAssetAddress: '0xfa2958cb79b0491cc627c1557f441ef849ca8eb1', // USDC on XDC (or AUDD when switching)
```

Update the `ChainConfig` interface and all chain entries. Add a comment per chain indicating the actual token:
```typescript
base: {
    stableAssetAddress: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', // USDC
    ...
},
xdc: {
    stableAssetAddress: '0x...', // AUDD (Australian Dollar stablecoin, 6 decimals)
    ...
},
```

#### 1.2 Update Environment Variables

Support both old and new names with fallback:
```typescript
// In chains.ts or deploy_1.ts
const stableAssetOverride = process.env.STABLE_ASSET_ADDRESS || process.env.USDC_ADDRESS;
const deployMockStable = resolveBooleanEnv('DEPLOY_MOCK_STABLE',
    resolveBooleanEnv('DEPLOY_MOCK_USDC', isLocal));
```

Update `.env.example`:
```bash
# Stable asset configuration
STABLE_ASSET_ADDRESS=         # Override chain config stable asset address (was: USDC_ADDRESS)
DEPLOY_MOCK_STABLE=           # Deploy mock stable token for testing (was: DEPLOY_MOCK_USDC)
# Legacy names still supported:
# USDC_ADDRESS, DEPLOY_MOCK_USDC
```

#### 1.3 Rename `usdc.ts` Module

Rename `scripts/_modules/usdc.ts` to `scripts/_modules/stableAsset.ts`:
```typescript
// Before
export function getUsdcContract() { ... }
export function isMockUsdc() { ... }
export function fundUsdcUsers() { ... }

// After
export function getStableAssetContract() { ... }
export function isMockStable() { ... }
export function fundStableAssetUsers() { ... }
```

Update all import sites across scripts.

#### 1.4 Update `deploy_1.ts`

Rename internal variable `usdcAddress` to `stableAssetAddress`. Update log messages:
```typescript
console.log('stable asset address: ', stableAssetAddress || '(will deploy mock)');
```

### Phase 2: Deployment JSON Key (Do With Multi-Asset)

**Do NOT rename the `"USDC"` key in deployment JSON files now.** This key is read by:
- `scripts/_modules/usdc.ts` (→ `stableAsset.ts`)
- Possibly external tooling or documentation

Renaming would require updating all existing deployment files across chains (Base, Plume, XDC) and any scripts that read them. This is better done when multi-asset support lands, since at that point the storage concept changes entirely.

For now, `stableAsset.ts` continues to read `addresses.USDC.address` internally — the function name is generic but the key is still `"USDC"`.

### Phase 3: Tests (Optional, Defer)

These are cosmetic changes with zero functional impact:

- Rename `MockUSDC.sol` → `MockStableAsset.sol` (or keep as-is)
- Rename test variables `usdc` → `stableAsset`
- Update `BaseTestUtils.sol` naming

**Recommendation**: Defer to multi-asset work where test infrastructure changes significantly anyway.

### Phase 4: Contract Comments (Optional, Defer)

Update the 23 USDC comment references in `src/` to say "stable asset" or "underlying asset". Zero functional impact. Can be done as part of any PR touching those files.

## Switching XDC from USDC to AUDD

### On-Chain State (verified 2026-03-07)

The XDC deployment currently uses USDC (`0xfa2958cb79b0491cc627c1557f441ef849ca8eb1`, token name: "USDC", 6 decimals).

**Active pool: `0x20F42FB45f91657aCf9528b99a5a16d0229C7800`**

| Metric | Value | Interpretation |
|--------|-------|----------------|
| `totalSupply` | 5,038,554 | 5.038554 LP tokens minted |
| `availableFunds` | 0 | All funds have been drawn |
| `userOwedAmount` | 5,038,554 | Borrower owes ~5.04 USDC |
| `feesOwedAmount` | 4,282 | ~0.004 USDC in fees owed |
| USDC balance of pool | 0 | No USDC sitting in pool |
| Tranches | 3 | Senior/Mezzanine/Junior |

**Tranche with deposit: `0xdd18a8ffda3d307ca500ed29679876cdace7b91a` (tranche index 1)**

| Metric | Value | Interpretation |
|--------|-------|----------------|
| `totalSupply` | 5,000,000,000,000,000,000 | 5e18 ERC4626 shares (18 decimal offset) |
| `totalAssets` | 5,038,554 | 5.038554 LP tokens worth of assets |

Other two tranches (index 0 and 2) have zero supply/assets.
Other two pools (`0x3b7cb...` and `0xEDa50...`) have zero state (no deposits).

**Contracts with USDC address baked into bytecode** (via `_underlyingAsset` immutable):

| Contract | Occurrences | Proxy Type |
|----------|-------------|------------|
| LendingPoolManager | 4 | TransparentProxy |
| LendingPool | 3 | BeaconProxy |
| PendingPool | 3 | BeaconProxy |
| LendingPoolTranche | 2 | BeaconProxy |
| FeeManager | 2 | TransparentProxy |

All other contracts (KasuController, KSULocking, KsuPrice, SystemVariables, FixedTermDeposit, UserLoyaltyRewards, UserManager, Swapper, KasuAllowList, ClearingCoordinator, LendingPoolFactory) do **not** have the USDC address in their bytecode.

### Will Switching Break the Existing $10 Deposit?

**Yes — switching the underlying asset on the current deployment would break it.**

The $10 deposit (now ~$5.04 after clearing/draw) created real on-chain state:

1. **LP tokens** — `LendingPool` has `totalSupply = 5,038,554` (ERC20 tokens representing pool value in USDC)
2. **Tranche shares** — `LendingPoolTranche` has `totalSupply = 5e18` shares backed by `totalAssets = 5,038,554` (LP tokens valued in USDC)
3. **Owed amount** — `userOwedAmount = 5,038,554` means the borrower owes 5.038554 USDC. If the underlying asset changes to AUDD, the contract would expect repayment in AUDD but the debt was originated in USDC
4. **Fees owed** — `feesOwedAmount = 4,282` — same problem, fees denominated in USDC

If we upgrade implementations to use AUDD as `_underlyingAsset`:
- `_transferAssets()` would call `AUDD.safeTransfer()` instead of `USDC.safeTransfer()`
- Repayment of the 5.04 owed amount would need to be in AUDD, but the original deposit was USDC
- The depositor would receive AUDD back instead of USDC on withdrawal
- The LP token and tranche share balances are unitless numbers — they don't inherently break, but their value interpretation changes from USDC to AUDD

**This is accounting corruption.** The depositor put in ~$5 USDC and would get back ~$5 AUDD (different value).

### Options for Switching

#### Option A: Clean Slate (Recommended)

1. **Close out the existing deposit**: repay the owed amount (5.04 USDC) + fees, process withdrawal, return USDC to depositor
2. **Verify all pools are empty**: `totalSupply = 0`, `userOwedAmount = 0`, `feesOwedAmount = 0` on all pools
3. **Upgrade all 5 contracts** with new implementations compiled against AUDD address:
   - Deploy new implementations: `forge build` with AUDD address in constructor args
   - Beacon upgrades: `beacon.upgradeTo(newImpl)` for LendingPool, PendingPool, LendingPoolTranche
   - Proxy upgrades: `proxyAdmin.upgradeAndCall(proxy, newImpl, "")` for LendingPoolManager, FeeManager
4. **Update `chains.ts`**: set `usdcAddress` (or `stableAssetAddress` post-rename) to AUDD address
5. **Update deployment JSON**: change `"USDC"` entry address to AUDD address (or add new entry)
6. Accept new deposits in AUDD

#### Option B: Fresh Deployment

1. Deploy entirely new set of contracts with AUDD as underlying asset
2. Simpler but means new proxy addresses, new deployment file
3. Old USDC deployment would need to be wound down separately

#### Option C: Keep Both (Multi-Asset — future)

This is the full multi-asset approach documented in `docs/multi-asset/`. Existing USDC stays as base asset, AUDD added as additional asset. Most complex but preserves everything.

### Recommendation

**Option A (Clean Slate)** — chosen approach. Skip the withdrawal step and accept the ~$5 value conversion. The existing deposit numbers are simply reinterpreted as AUDD.

**Why this is safe:**
- All token balances are zero — no USDC tokens are sitting in any contract (pool, pending pool, fee manager)
- The on-chain state is just numbers in storage (LP tokens, tranche shares, owed amounts) — they have no inherent currency denomination
- After upgrading, `_transferAssets()` calls route to AUDD instead of USDC — all future operations (repay, withdraw, deposit) use AUDD
- Only ~$5 of value affected by the USDC/AUDD rate difference

**What happens to existing state:**
- Borrower drew ~5.04 USDC but will repay ~5.04 AUDD (~$3.15 USD) — borrower benefits slightly
- Depositor put in ~5 USDC but will withdraw ~5.04 AUDD (~$3.15 USD) — depositor loses ~$1.85
- Acceptable given the trivial amount

### Upgrade Procedure

```bash
# 1. Update chains.ts with AUDD address
# usdcAddress: '<AUDD_TOKEN_ADDRESS_ON_XDC>'

# 2. Deploy new implementations (same Solidity, compiled with AUDD in constructor)
# Then upgrade 5 contracts via multisig batch transaction:
#   - Beacon upgrades: LendingPool, PendingPool, LendingPoolTranche
#   - Proxy upgrades: LendingPoolManager, FeeManager

# 3. Validate
npx hardhat --network xdc run scripts/smokeTests/validateDeploymentComplete.ts
npx hardhat --network xdc run scripts/admin/validateDeployment.ts
```

### For a Fresh Deployment with AUDD (Option B)

Simply set the AUDD address in `chains.ts` and deploy. No code changes needed. The contracts are asset-agnostic.

## Impact Summary

| Category | Files Affected | Risk | Priority |
|----------|---------------|------|----------|
| `chains.ts` field rename | ~5 script files | Low | High |
| Env var rename (with fallback) | `.env.example`, `deploy_1.ts` | Low | High |
| `usdc.ts` module rename | ~10 script files importing it | Low | High |
| `deploy_1.ts` variable names | 1 file | Low | High |
| Deployment JSON key | 3 address files + readers | Medium | Defer |
| Test naming | ~8 test files | Low | Defer |
| Contract comments | ~15 source files | None | Defer |
