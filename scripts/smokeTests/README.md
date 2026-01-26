# Kasu Deployment Smoke Tests

Post-deployment validation scripts to ensure the Kasu protocol is correctly configured and secured.

## Overview

These smoke tests validate critical deployment aspects:

1. **Proxy & Beacon Ownership**: All ProxyAdmin and Beacon contracts are owned by the multisig (not deployer)
2. **Role Configuration**: Critical roles are set correctly on KasuController
3. **Protocol Configuration**: Protocol fee receiver and other settings are properly configured

## Usage

Run smoke tests after deployment to validate the setup:

```bash
# Complete deployment validation (recommended)
# Automatically discovers and validates all pools!
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts

# Basic role and ownership validation (quick check, no pool validation)
npx hardhat --network base run scripts/smokeTests/validateRolesAndOwnership.ts

# Standalone pool-specific role validation (also auto-discovers pools)
npx hardhat --network base run scripts/smokeTests/validatePoolRoles.ts
```

**Manual pool specification (optional):**
```bash
# Override auto-discovery by specifying pool addresses manually
LENDING_POOL_ADDRESSES=0xpool1,0xpool2 \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

### For Different Networks

```bash
# Base mainnet
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts

# Plume mainnet (Blockscout - no API key required)
npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts
# See PLUME_RESULTS.md for latest test results and issues found

# XDC mainnet
npx hardhat --network xdc run scripts/smokeTests/validateDeploymentComplete.ts

# Local testing
npx hardhat --network localhost run scripts/smokeTests/validateDeploymentComplete.ts
```

**Network-Specific Notes:**
- **Base:** Uses Etherscan V2 API (requires `ETHERSCAN_API_KEY`)
- **Plume:** Uses Blockscout API (free, no API key required)
- **XDC:** Uses XDC Explorer API (requires `ETHERSCAN_API_KEY` - same key works via Etherscan V2)

## Scripts

### validateRolesAndOwnership.ts

Basic validation script that checks:
- ProxyAdmin ownership for all TransparentProxy contracts
- Beacon ownership for all UpgradeableBeacon contracts
- ROLE_KASU_ADMIN assignment
- ROLE_LENDING_POOL_FACTORY assignment

**When to use**: Quick validation of critical ownership and admin roles.

### validateDeploymentComplete.ts (Recommended - All-in-One)

**THE** comprehensive validation script - validates everything automatically!

**Proxy & Beacon Ownership**
- All ProxyAdmin contracts owned by Kasu multisig (not deployer)
- All Beacon contracts owned by Kasu multisig (not deployer)

**Role Configuration on KasuController (Global)**
- ✅ Kasu multisig has ROLE_KASU_ADMIN
- ✅ Deployer does NOT have ROLE_KASU_ADMIN (should be revoked after deployment)
- ✅ ROLE_LENDING_POOL_FACTORY is assigned (to LendingPoolFactory contract)
- ✅ Pool admin multisig has ROLE_LENDING_POOL_CREATOR
- ✅ ROLE_PROTOCOL_FEE_CLAIMER is assigned (prints who has it)

**Protocol Configuration**
- ✅ protocolFeeReceiver is set (prints the address) and is not the deployer account

**Pool-Specific Roles (Auto-discovered)**
- ✅ Automatically discovers all pools via `PoolCreated` events
- ✅ Pool admin multisig has ROLE_POOL_ADMIN (per pool)
- ✅ Pool admin multisig has ROLE_POOL_CLEARING_MANAGER (per pool)
- ✅ Pool manager multisig has ROLE_POOL_MANAGER (per pool)
- ✅ Pool manager multisig has ROLE_POOL_FUNDS_MANAGER (per pool)

**Tenderly Simulation (Optional)**
- ✅ Simulates `lendingPoolManager.createPool()` transaction
- ✅ Verifies LENDING_POOL_CREATOR role works correctly
- ✅ Tests without on-chain execution (no gas cost)
- ⚠️  Requires Tenderly credentials (skips if not configured)
- 💡 Set `TENDERLY_ACCESS_KEY`, `TENDERLY_ACCOUNT_ID`, `TENDERLY_PROJECT_SLUG` to enable

**When to use**: Post-deployment validation. Just run it - it handles everything automatically!

**Note**: If auto-discovery fails (e.g., event logs unavailable), you can manually specify pools via `LENDING_POOL_ADDRESSES`.

## Configuration

### Pool Addresses (Required for Pool Validation)

**Add pool addresses to `scripts/_config/chains.ts`:**

```typescript
base: {
    name: 'Base Mainnet',
    chainId: 8453,
    // ... other config ...
    lendingPoolAddresses: [
        '0xYourPool1Address',
        '0xYourPool2Address',
        '0xYourPool3Address',
    ],
    isTestnet: false,
}
```

Pool addresses are **public on-chain data** (not sensitive), so they belong in the config file with other chain-specific deployment information.

**Environment variable override** (optional):

```bash
# Temporarily override pool addresses for testing
LENDING_POOL_ADDRESSES=0xPool1,0xPool2,0xPool3 \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

**Why not auto-discovery?**
- Mainnet has millions of blocks to scan
- Free tier RPC providers have strict rate limits (10k blocks per query on Alchemy)
- Scanning would take hundreds of queries and several minutes
- Manual specification in config is instant and reliable

**Auto-discovery fallback:**
If no pools are configured, the script will attempt auto-discovery (works for local/testnet with recent deployments).

### Kasu Multisig Addresses

Configure the multisig for your network in `scripts/_config/chains.ts`:

```typescript
base: {
    kasuMultisig: '0xC3128d734563E0d034d3ea177129657408C09D35',
    // ...
}
```

Or override via environment variable:

```bash
KASU_MULTISIG=0x... npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

### Current Multisig Addresses

#### Kasu Multisig (Proxy ownership & ROLE_KASU_ADMIN)

| Network | Address |
|---------|---------|
| Base    | `0xC3128d734563E0d034d3ea177129657408C09D35` |
| Plume   | `0x344BA98De46750e0B7CcEa8c3922Db8A70391189` |
| XDC     | `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D` |

#### Pool Manager Multisig (ROLE_POOL_MANAGER & ROLE_POOL_FUNDS_MANAGER)

| Network | Address |
|---------|---------|
| Base    | `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2` |
| Plume   | `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe` |
| XDC     | _Not set yet_ |

#### Pool Admin Multisig (ROLE_LENDING_POOL_CREATOR, ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER)

| Network | Address |
|---------|---------|
| Base    | `0x7adf999af5E0617257014C94888cf98c4584E5E9` |
| Plume   | `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF` |
| XDC     | _Not set yet_ |

### Deployer Address Validation

To validate that the deployer doesn't retain admin privileges, you can set either:

1. **`DEPLOYER_KEY`** - The deployer's private key (allows full validation)
2. **`DEPLOYER_ADDRESS`** - The deployer's address only (read-only validation, no private key needed)

Set in `scripts/_env/.{network}.env`:
```bash
# Option 1: Private key (for deployment + validation)
DEPLOYER_KEY=0x...

# Option 2: Address only (for read-only validation)
DEPLOYER_ADDRESS=0x...
```

If neither is set, deployer-specific checks will be skipped (but multisig validation will still run).

## Expected Output

### Success Example

```
========================================
Kasu Deployment Smoke Test
Complete Validation
========================================

Network: Base Mainnet (base)
Block: 12345678
Kasu Multisig: 0xC3128d734563E0d034d3ea177129657408C09D35
Deployer: 0x1234...

📋 Validating Proxy & Beacon Ownership...
📋 Validating Roles on KasuController...
📋 Validating Protocol Configuration...

--- Proxy Ownership ---
✅ KasuController: ProxyAdmin correctly owned by multisig
✅ LendingPoolManager: ProxyAdmin correctly owned by multisig
...

--- Roles ---
✅ ROLE_KASU_ADMIN: Multisig has the role
✅ ROLE_KASU_ADMIN: Deployer correctly does NOT have admin role
✅ ROLE_PROTOCOL_FEE_CLAIMER: Set to 0x...
✅ ROLE_LENDING_POOL_FACTORY: Set to 0x...
✅ ROLE_LENDING_POOL_CREATOR: Set to 0x...

--- Protocol Config ---
✅ protocolFeeReceiver: Set to 0x...

========================================
Summary
========================================
Total checks: 15
✅ Passed: 15
❌ Failed: 0
========================================

✅ All smoke tests PASSED
```

### Failure Example

```
❌ KasuController: ProxyAdmin still owned by deployer (0x1234...)
❌ ROLE_KASU_ADMIN: Multisig does NOT have the role
❌ ROLE_PROTOCOL_FEE_CLAIMER: No accounts have this role

========================================
Summary
========================================
Total checks: 15
✅ Passed: 12
❌ Failed: 3
========================================

❌ Smoke test FAILED - Please review failed checks above
```

## Common Failures and Fixes

### "ProxyAdmin still owned by deployer"

The deployer account still owns the ProxyAdmin contracts. Transfer ownership:

```bash
NEW_PROXY_ADMIN_OWNER=0xMultisigAddress npx hardhat --network base run scripts/admin/transferAllProxyAdminOwnership.ts
```

### "Deployer still has admin role"

Revoke the ROLE_KASU_ADMIN from the deployer account using the multisig.

### "ROLE_PROTOCOL_FEE_CLAIMER: No accounts have this role"

Grant the role to the appropriate account using KasuController.grantRole() from the admin account.

### "protocolFeeReceiver: Not set"

Set the protocol fee receiver in SystemVariables by calling `setProtocolFeeReceiver()` from an admin account:
```solidity
systemVariables.setProtocolFeeReceiver(receiverAddress);
```

## Integration with CI/CD

These smoke tests can be integrated into deployment pipelines:

```bash
# Deploy
DEPLOYMENT_MODE=full npx hardhat --network base deploy

# Run smoke tests
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts || exit 1

# If tests pass, continue with additional setup
```

## See Also

- **`VALIDATION_FLOW.md`** - Complete step-by-step validation workflow (start here!)
- **`AUTO_DISCOVERY.md`** - How automatic pool discovery works
- **`ROLES_REFERENCE.md`** - Complete role assignment reference
- **`CHECKLIST.md`** - Post-deployment validation checklist
- `scripts/admin/printProxyAdmins.ts` - View all ProxyAdmin and Beacon owners
- `scripts/admin/transferAllProxyAdminOwnership.ts` - Transfer ownership to multisig
- `scripts/admin/validateDeployment.ts` - Validate bytecode matches source
