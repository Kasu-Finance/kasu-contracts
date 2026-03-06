# Migration & Backwards Compatibility

## Upgrade Strategy

All changes are **additive** — new storage variables appended to existing contracts, new methods added alongside existing ones. No existing storage is modified or reordered.

### Proxy Types and Upgrade Mechanisms

| Contract | Proxy Type | Upgrade Mechanism |
|----------|-----------|-------------------|
| LendingPoolManager | TransparentUpgradeableProxy | ProxyAdmin.upgradeAndCall() |
| LendingPool | BeaconProxy | UpgradeableBeacon.upgradeTo() — upgrades ALL pool proxies at once |
| PendingPool | BeaconProxy | UpgradeableBeacon.upgradeTo() — upgrades ALL pending pool proxies |
| LendingPoolTranche | BeaconProxy | UpgradeableBeacon.upgradeTo() — upgrades ALL tranche proxies |
| ClearingCoordinator | TransparentUpgradeableProxy | ProxyAdmin.upgradeAndCall() |
| FeeManager | TransparentUpgradeableProxy | ProxyAdmin.upgradeAndCall() |
| FixedTermDeposit | TransparentUpgradeableProxy | ProxyAdmin.upgradeAndCall() |

### Storage Layout Safety

**Contracts with `__gap` (safe for ~50 new uint256 slots):**
- LendingPoolManager (via KasuAccessControllable)
- FeeManager (via KasuAccessControllable)
- ClearingCoordinator (via LendingPoolHelpers — needs verification)

**Contracts WITHOUT `__gap` (appending still safe, just no reserved slots):**
- LendingPool — 4 immutables + 8 state variables, new mappings appended after `nextLossId`
- PendingPool — 3 immutables + 10 state variables, new mappings appended after `_totalUserTranchePendingDepositAmount`
- LendingPoolTranche — 2 immutables + 3 state variables + LendingPoolTrancheLoss state, new mappings appended after `_trancheUsers`
- FixedTermDeposit — 1 immutable + 8 state variables, new mappings appended

**Recommendation**: Add `uint256[50] private __gap;` to LendingPool, PendingPool, LendingPoolTranche, and FixedTermDeposit in this upgrade to reserve space for future changes.

### Pre-Upgrade Validation

Before deploying upgrades:

1. **Storage layout verification** — Use `hardhat-upgrades` plugin's `validateUpgrade()` to verify storage compatibility:
   ```bash
   npx hardhat run scripts/admin/validateStorageLayout.ts
   ```

2. **Bytecode comparison** — Use existing `validateDeployment.ts` to confirm implementation changes match source.

3. **Tenderly simulation** — Simulate the beacon upgrade on Base to verify no storage corruption.

## Backwards Compatibility

### Pre-Upgrade Deposits

All deposits made before the upgrade have no entry in `_depositAsset[dNftID]`. The default value for an unset mapping key is `address(0)`.

**Convention**: `address(0)` = base asset (USDC).

All existing code paths check:
```solidity
address asset = _depositAsset[dNftID];
if (asset == address(0)) {
    // Use existing base asset flow (unchanged)
} else {
    // Use new additional asset flow
}
```

This means:
- Pre-upgrade deposit NFTs continue to work identically
- Pre-upgrade withdrawal NFTs continue to work identically
- Pre-upgrade clearing processes are unaffected
- Pre-upgrade LP tokens (ERC20) and tranche shares (ERC4626) are unaffected

### Existing Public Method Signatures — UNCHANGED

Every existing public/external method signature remains identical:

| Method | Change |
|--------|--------|
| `LendingPoolManager.requestDeposit(...)` | Unchanged — always uses base asset |
| `LendingPoolManager.requestDepositWithKyc(...)` | Unchanged |
| `LendingPoolManager.requestWithdrawal(...)` | Unchanged |
| `LendingPoolManager.cancelDepositRequest(...)` | Unchanged |
| `LendingPoolManager.cancelWithdrawalRequest(...)` | Unchanged |
| `LendingPoolManager.repayOwedFunds(...)` | Unchanged |
| `LendingPoolManager.depositFirstLossCapital(...)` | Unchanged |
| `LendingPoolManager.forceImmediateWithdrawal(...)` | Unchanged |
| `LendingPoolManager.createPool(...)` | Unchanged |
| `PendingPool.requestDeposit(...)` | Unchanged |
| `PendingPool.requestWithdrawal(...)` | Unchanged |
| `LendingPool.acceptDeposit(...)` | Unchanged |
| `LendingPool.acceptWithdrawal(...)` | Unchanged |
| `LendingPool.drawFunds(...)` | Unchanged |
| `LendingPool.repayOwedFunds(...)` | Unchanged |
| `LendingPool.applyInterests(...)` | Unchanged |
| `ClearingCoordinator.doClearing(...)` | Unchanged |
| `FeeManager.emitFees(...)` | Unchanged |
| `FeeManager.claimProtocolFees()` | Unchanged |

New methods are **added alongside** existing ones — they do not replace them.

### Pools Without Additional Assets

Pools that never have additional assets configured behave exactly as they do today. No additional storage is written, no additional gas is consumed. The feature is fully opt-in per pool.

## Deployment Steps

### Phase 1: Deploy New Implementations

```bash
# Deploy new implementation contracts (not yet upgraded)
npx hardhat run scripts/upgrade/deployMultiAssetImplementations.ts --network base
```

This deploys:
- New LendingPool implementation
- New PendingPool implementation
- New LendingPoolTranche implementation
- New LendingPoolManager implementation
- New ClearingCoordinator implementation
- New FeeManager implementation
- New FixedTermDeposit implementation

### Phase 2: Validate

```bash
# Compare storage layouts
npx hardhat run scripts/admin/validateStorageLayout.ts --network base

# Simulate upgrades via Tenderly
npx hardhat run scripts/admin/simulateUpgrade.ts --network base
```

### Phase 3: Execute Upgrades via Multisig

Generate multisig transaction batch:

```bash
npx hardhat run scripts/multisig/generateMultiAssetUpgradeBatch.ts --network base
```

This produces a JSON file for Gnosis Safe Transaction Builder with:
1. Beacon upgrades (LendingPool, PendingPool, LendingPoolTranche)
2. ProxyAdmin upgrades (LendingPoolManager, ClearingCoordinator, FeeManager, FixedTermDeposit)

### Phase 4: Configure Additional Assets

After upgrade, configure pools:

```bash
# Add AUDD as additional asset for a specific pool
LENDING_POOL_ADDRESS=0x... ASSET_ADDRESS=0x... \
  npx hardhat run scripts/admin/addPoolAdditionalAsset.ts --network base
```

### Phase 5: Validate Deployment

```bash
# Run smoke tests
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts

# Validate bytecode
npx hardhat --network base run scripts/admin/validateDeployment.ts
```

## Rollback Plan

If issues are discovered post-upgrade:

### Beacon Contracts (LendingPool, PendingPool, LendingPoolTranche)

Beacon upgrades can be rolled back by pointing the beacon back to the previous implementation:

```solidity
beacon.upgradeTo(previousImplementationAddress);
```

Since new storage is only **appended** and never read by the old implementation, rolling back is safe. The new storage slots simply become unused (but retain their values for potential re-upgrade).

### TransparentProxy Contracts

Similarly, ProxyAdmin can upgrade back to the previous implementation. Appended storage is ignored by the old implementation.

### Data Migration

No data migration is needed in either direction. The upgrade is purely additive.

## Multi-Chain Deployment

The upgrade follows the same pattern on all chains:

| Chain | Mode | Additional Notes |
|-------|------|-----------------|
| Base | Full | Primary deployment, upgrade via Kasu multisig |
| Plume | Lite | Lite contracts need corresponding Lite+MultiAsset implementations |
| XDC | Lite | Same as Plume |

### Lite Contract Considerations

Lite contracts (e.g., `UserManagerLite`, `ProtocolFeeManagerLite`) that override base functionality will also need multi-asset awareness. Specifically:
- `ProtocolFeeManagerLite` — needs `emitFeesInAsset()` and `claimProtocolFeesInAsset()`
- Other Lite contracts are unaffected (they don't touch asset transfers)

## Interface Versioning

New interfaces can extend existing ones:

```solidity
interface ILendingPoolV2 is ILendingPool {
    function acceptDepositInAsset(...) external returns (uint256);
    function acceptWithdrawalInAsset(...) external returns (uint256);
    // ...
}
```

Or the new methods can be added directly to existing interfaces (since all implementations are upgraded simultaneously via beacon/proxy).

**Recommended**: Add directly to existing interfaces. All implementations are upgraded atomically per-chain, so there's no risk of interface mismatch.
