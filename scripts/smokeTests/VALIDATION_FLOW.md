# Kasu Deployment Validation Flow

Complete post-deployment validation workflow for Kasu protocol.

## One-Step Validation (Recommended)

Simply run the comprehensive validation - it automatically discovers and validates all pools:

```bash
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

This automatically validates:
- ✅ All proxy & beacon ownership
- ✅ All global roles
- ✅ Protocol configuration
- ✅ **Auto-discovers pools** via `PoolCreated` events
- ✅ Pool-specific roles for all discovered pools

**No manual pool specification needed!** The script queries `PoolCreated` events to find all pools.

## Step-by-Step Validation (Alternative)

### Step 1: Global Deployment Validation

Run without pool addresses to validate global configuration only:

```bash
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

### What Gets Checked

**Ownership & Security**
- ✅ All ProxyAdmin contracts owned by Kasu multisig
- ✅ All Beacon contracts owned by Kasu multisig
- ✅ Deployer does NOT own any ProxyAdmins
- ✅ Deployer does NOT own any Beacons

**Global Roles**
- ✅ Kasu multisig has ROLE_KASU_ADMIN
- ✅ Deployer does NOT have ROLE_KASU_ADMIN
- ✅ LendingPoolFactory has ROLE_LENDING_POOL_FACTORY
- ✅ Pool admin multisig has ROLE_LENDING_POOL_CREATOR

**Protocol Configuration**
- ✅ ROLE_PROTOCOL_FEE_CLAIMER assigned → prints address
- ✅ protocolFeeReceiver is set → prints address
- ✅ protocolFeeReceiver is NOT deployer

### Expected Output

```
========================================
Kasu Deployment Smoke Test
Complete Validation
========================================

Network: Base Mainnet (base)
Kasu Multisig: 0xC3128d734563E0d034d3ea177129657408C09D35
Pool Manager Multisig: 0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2
Pool Admin Multisig: 0x7adf999af5E0617257014C94888cf98c4584E5E9
Deployer: 0x...

--- Proxy Ownership ---
✅ KasuController: ProxyAdmin correctly owned by multisig
✅ LendingPoolManager: ProxyAdmin correctly owned by multisig
...

--- Roles ---
✅ ROLE_KASU_ADMIN: Kasu multisig has the role
✅ ROLE_KASU_ADMIN: Deployer correctly does NOT have admin role
✅ ROLE_LENDING_POOL_FACTORY: LendingPoolFactory has the role
✅ ROLE_LENDING_POOL_CREATOR: Pool admin multisig has the role
✅ ROLE_PROTOCOL_FEE_CLAIMER: Granted to 0x...

--- Protocol Config ---
✅ protocolFeeReceiver: 0x...

========================================
Summary
========================================
Total checks: 15
✅ Passed: 15
❌ Failed: 0
========================================

✅ All smoke tests PASSED
```

### Step 2: Pool-Specific Role Validation

After creating lending pools, the comprehensive validation (`validateDeploymentComplete.ts`) will automatically discover and validate them. No additional steps needed!

If you want standalone pool validation:
```bash
npx hardhat --network base run scripts/smokeTests/validatePoolRoles.ts
```

**Manual override** (if auto-discovery fails):
```bash
LENDING_POOL_ADDRESSES=0xpool1,0xpool2,0xpool3 \
  npx hardhat --network base run scripts/smokeTests/validatePoolRoles.ts
```

### What Gets Checked (Per Pool)

For each pool, validates that the correct multisigs have pool-specific roles:

**Pool Admin Multisig**
- ✅ Has ROLE_POOL_ADMIN for this pool
- ✅ Has ROLE_POOL_CLEARING_MANAGER for this pool

**Pool Manager Multisig**
- ✅ Has ROLE_POOL_MANAGER for this pool
- ✅ Has ROLE_POOL_FUNDS_MANAGER for this pool

### Expected Output

```
========================================
Kasu Pool-Specific Role Validation
========================================

Network: Base Mainnet (base)
Pool Manager Multisig: 0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2
Pool Admin Multisig: 0x7adf999af5E0617257014C94888cf98c4584E5E9

Validating 2 pool(s)...

📋 Validating pool: 0xPoolAddress1

  ✅ ROLE_POOL_ADMIN: Pool admin multisig has ROLE_POOL_ADMIN
  ✅ ROLE_POOL_CLEARING_MANAGER: Pool admin multisig has ROLE_POOL_CLEARING_MANAGER
  ✅ ROLE_POOL_MANAGER: Pool manager multisig has ROLE_POOL_MANAGER
  ✅ ROLE_POOL_FUNDS_MANAGER: Pool manager multisig has ROLE_POOL_FUNDS_MANAGER

📋 Validating pool: 0xPoolAddress2

  ✅ ROLE_POOL_ADMIN: Pool admin multisig has ROLE_POOL_ADMIN
  ✅ ROLE_POOL_CLEARING_MANAGER: Pool admin multisig has ROLE_POOL_CLEARING_MANAGER
  ✅ ROLE_POOL_MANAGER: Pool manager multisig has ROLE_POOL_MANAGER
  ✅ ROLE_POOL_FUNDS_MANAGER: Pool manager multisig has ROLE_POOL_FUNDS_MANAGER

========================================
Summary
========================================
Pools validated: 2
Total checks: 8
✅ Passed: 8
❌ Failed: 0
========================================

✅ All pool role validations PASSED
```

## Step 3: Additional Validations

### Contract Verification

Validate bytecode matches source:

```bash
DEPLOYMENT_MODE=full npx hardhat --network base run scripts/admin/validateDeployment.ts
```

### Proxy Ownership Review

Print all ProxyAdmin and Beacon owners:

```bash
npx hardhat --network base run scripts/admin/printProxyAdmins.ts
```

## Common Failures & Fixes

### ❌ Deployer still has ROLE_KASU_ADMIN

From Kasu multisig, revoke the role:
```solidity
kasuController.revokeRole(ROLE_KASU_ADMIN, deployerAddress);
```

### ❌ ROLE_PROTOCOL_FEE_CLAIMER not granted

From Kasu multisig, grant the role:
```solidity
kasuController.grantRole(ROLE_PROTOCOL_FEE_CLAIMER, feeClaimerAddress);
```

### ❌ protocolFeeReceiver not set or is deployer

From admin account:
```solidity
systemVariables.setProtocolFeeReceiver(receiverAddress);
```

### ❌ Pool-specific role missing

From Kasu multisig or pool admin:
```solidity
kasuController.grantLendingPoolRole(poolAddress, role, multisigAddress);
```

For example:
```solidity
kasuController.grantLendingPoolRole(
    0xPoolAddress,
    ROLE_POOL_MANAGER,
    0xPoolManagerMultisig
);
```

### ❌ ProxyAdmin still owned by deployer

Transfer all ProxyAdmin ownership:
```bash
NEW_PROXY_ADMIN_OWNER=0xKasuMultisig \
  npx hardhat --network base run scripts/admin/transferAllProxyAdminOwnership.ts
```

## Environment Setup

### Required for Read-Only Validation

```bash
# In scripts/_env/.base.env
DEPLOYER_ADDRESS=0x...  # For deployer privilege checks
```

### Required for Pool Validation

```bash
# Pass as environment variable
LENDING_POOL_ADDRESSES=0xpool1,0xpool2,0xpool3
```

## Network-Specific Configs

Multisig addresses are configured in `scripts/_config/chains.ts`:

```typescript
base: {
    kasuMultisig: '0xC3128d734563E0d034d3ea177129657408C09D35',
    poolManagerMultisig: '0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2',
    poolAdminMultisig: '0x7adf999af5E0617257014C94888cf98c4584E5E9',
}
```

Override via env if needed:
```bash
KASU_MULTISIG=0x... \
POOL_MANAGER_MULTISIG=0x... \
POOL_ADMIN_MULTISIG=0x... \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

## npm Shortcuts

```bash
# Runs on localhost by default (change --network in package.json)
npm run scripts:smokeTest           # Full validation
npm run scripts:smokeTest:roles     # Quick role check
npm run scripts:smokeTest:pools     # Pool-specific validation
```

## Checklist

- [ ] Run `validateDeploymentComplete.ts` - All global checks pass
- [ ] Transfer ProxyAdmin ownership if needed
- [ ] Revoke ROLE_KASU_ADMIN from deployer
- [ ] Set ROLE_PROTOCOL_FEE_CLAIMER if not set
- [ ] Set protocolFeeReceiver if not set
- [ ] Create lending pools
- [ ] Run `validateDeploymentComplete.ts` again - All checks pass (pools auto-discovered)
- [ ] Verify contracts on block explorer
- [ ] Document pool addresses and transaction hashes
