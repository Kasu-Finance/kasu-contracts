# Plume Smoke Test Results

**Date:** January 26, 2026
**Network:** Plume Mainnet (Chain ID: 98866)
**Block:** 48,215,269
**Explorer:** https://explorer.plume.org (Blockscout)

## Executive Summary

Smoke tests successfully ran on Plume and revealed **4 critical role configuration issues** that must be addressed before the deployment is production-ready. All proxy ownership is correctly configured.

## Test Command

```bash
npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts
```

## Results Overview

- **Total Checks:** 24
- **Passed:** 20 ✅
- **Failed:** 4 ❌
- **Status:** FAILED (roles not granted)

## ✅ What's Working

### Proxy & Beacon Ownership (18/18 checks passed)

All contracts are correctly owned by the Kasu multisig (`0x344BA98De46750e0B7CcEa8c3922Db8A70391189`):

**ProxyAdmin Ownership (15 contracts):**
- KasuController
- KSULocking
- KsuPrice
- SystemVariables
- FixedTermDeposit
- UserLoyaltyRewards
- UserManager
- Swapper
- LendingPoolManager
- FeeManager
- KasuAllowList
- ClearingCoordinator
- AcceptedRequestsCalculation
- LendingPoolFactory
- KSULockBonus

**Beacon Ownership (3 beacons):**
- LendingPool
- PendingPool
- LendingPoolTranche

### Other Passing Checks

- ✅ ROLE_LENDING_POOL_FACTORY granted to LendingPoolFactory contract
- ✅ Protocol fee receiver is configured (`0x0e7e0a898ddBbE859d08976dE1673c7A9F579483`)

## ❌ Critical Issues Found

### 1. ROLE_KASU_ADMIN Not Granted

**Issue:** Kasu multisig does NOT have ROLE_KASU_ADMIN
**Impact:** Cannot perform administrative actions on KasuController
**Address:** `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`

**Fix:**
```solidity
// Caller must be current admin (likely deployer)
kasuController.grantRole(ROLE_KASU_ADMIN, 0x344BA98De46750e0B7CcEa8c3922Db8A70391189);
```

### 2. ROLE_LENDING_POOL_CREATOR Not Granted

**Issue:** Pool admin multisig does NOT have ROLE_LENDING_POOL_CREATOR
**Impact:** Cannot create new lending pools
**Address:** `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF`

**Fix:**
```solidity
// Caller must have KASU_ADMIN role
kasuController.grantRole(
    ROLE_LENDING_POOL_CREATOR,
    0xEb8D4618713517C1367aCA4840b1fca3d8b090DF
);
```

### 3. ROLE_PROTOCOL_FEE_CLAIMER Not Granted

**Issue:** Expected address does NOT have ROLE_PROTOCOL_FEE_CLAIMER
**Impact:** Cannot claim protocol fees
**Expected Address:** `0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28`

**Fix:**
```solidity
// Caller must have KASU_ADMIN role
kasuController.grantRole(
    ROLE_PROTOCOL_FEE_CLAIMER,
    0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28
);
```

### 4. Tenderly Simulation Failed

**Issue:** Pool creation simulation reverted
**Cause:** Missing ROLE_LENDING_POOL_CREATOR (issue #2)
**Dashboard:** https://dashboard.tenderly.co/kivanov82/kasu/simulator/f05e0d23-f3b8-4737-81d2-b2ae5bea66a6

**Note:** This will automatically pass once issue #2 is resolved.

## Configuration Details

### Multisig Addresses

| Role | Address |
|------|---------|
| Kasu Multisig | `0x344BA98De46750e0B7CcEa8c3922Db8A70391189` |
| Pool Manager Multisig | `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe` |
| Pool Admin Multisig | `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF` |
| Protocol Fee Claimer | `0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28` |

### Key Contract Addresses

| Contract | Address |
|----------|---------|
| KasuController | `0x7923837dC93d897E12696e0F4FD50b51FBacf693` |
| LendingPoolManager | `0xe593edF0579cfa8b622C327c05A0070c71BAA6d2` |
| LendingPoolFactory | `0xA2e9992B73BE340eC7134e751A4E5358374Fb1d0` |
| KasuAllowList | `0xef956C2193e032609da84bEc5E5251B28939b6B9` |

## Deployment Info

**Deployment Date:** January 15, 2025
**Start Block:** 763,533
**Deployment Mode:** Lite (no KSU token functionality)
**Deployment Files:**
- `.openzeppelin/plume-addresses.json`
- `.openzeppelin/unknown-98866.json`

## Blockscout API Notes

✅ **Blockscout API works without API key**

- Explorer: https://explorer.plume.org
- API Base: https://explorer.plume.org/api/v2
- No authentication required for basic operations
- `PLUME_SCAN_API_KEY` is optional (can be empty)

**Example API Calls:**
```bash
# Get network stats
curl "https://explorer.plume.org/api/v2/stats"

# Get contract info
curl "https://explorer.plume.org/api/v2/addresses/0x7923837dC93d897E12696e0F4FD50b51FBacf693"

# Get contract logs/events
curl "https://explorer.plume.org/api/v2/addresses/0xA2e9992B73BE340eC7134e751A4E5358374Fb1d0/logs"
```

## Pool Status

**Current Pools:** None
**Auto-Discovery:** Skipped (48M+ blocks impractical to scan)

To specify pools manually:
```bash
LENDING_POOL_ADDRESSES=0xPool1,0xPool2 \
  npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts
```

## Contract Verification & Source Code Status

Ran deployment validation to check if on-chain bytecode matches local source:

```bash
DEPLOYMENT_MODE=lite AUTO_VERIFY=false npx hardhat --network plume run scripts/admin/validateDeployment.ts
```

### ✅ Source Code Matches (11 contracts)

These contracts match the local source code exactly:
- KasuController
- Swapper
- LendingPoolManager
- KasuAllowList
- ClearingCoordinator
- AcceptedRequestsCalculation
- LendingPool (Beacon)
- PendingPool (Beacon)
- LendingPoolTranche (Beacon)
- LendingPoolFactory
- KSULockBonus

### ⚠️ Source Code Mismatch - Needs Upgrade (7 contracts)

These contracts have different source code on-chain vs local (likely older versions):
- **KSULockingLite** - Implementation: `0x5D9b878744dbe721a3f33A60a6b102E289CeADBA`
- **KsuPriceLite** - Implementation: `0xb0D7Eb2D5036fB85A231D0E243a5b723BA5D2868`
- **SystemVariables** - Implementation: `0xB145C061684C701c2C018A3f322aa14F5A553CE1`
- **FixedTermDeposit** - Implementation: `0x221a54CbbD5f490Bd8e77CF36acBA4B1304E5c1b`
- **UserLoyaltyRewardsLite** - Implementation: `0xaFb2966dCc3f20eC4412162a8D203247a93A7765`
- **UserManagerLite** - Implementation: `0xF0e92ad317a315Adb21923aefce66Aaf55364bE9`
- **ProtocolFeeManagerLite** - Implementation: `0xd2812f27ee3D898daEF64772E113A13A0F80c229`

**Note:** All mismatched contracts are upgradeable proxies and can be upgraded to match the latest source code.

### To Upgrade Contracts

Run deployment script with `DEPLOY_UPDATES=true`:
```bash
DEPLOYMENT_MODE=lite DEPLOY_UPDATES=true npx hardhat --network plume deploy
```

## Action Items

### Immediate (Required for Production)

1. ✅ **Grant ROLE_KASU_ADMIN to Kasu multisig**
   - Use current admin account (likely deployer)
   - Target: `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`

2. ✅ **Grant ROLE_LENDING_POOL_CREATOR to pool admin multisig**
   - Use account with KASU_ADMIN role (after step 1)
   - Target: `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF`

3. ✅ **Grant ROLE_PROTOCOL_FEE_CLAIMER to fee claimer**
   - Use account with KASU_ADMIN role (after step 1)
   - Target: `0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28`

4. ✅ **Revoke deployer's ROLE_KASU_ADMIN** (security best practice)
   - Use Kasu multisig (after step 1)
   - Revoke from deployer address

5. ✅ **Re-run smoke tests to verify**
   ```bash
   npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts
   ```

### Optional

- Configure pool addresses in `scripts/_config/chains.ts` for faster validation (once pools are created)
- Set up Tenderly credentials for simulation testing (optional)

## Verification

After granting the missing roles, all 24 checks should pass:

```
========================================
Summary
========================================
Global checks: 24 (✅ 24, ❌ 0)
---
Total checks: 24
✅ Passed: 24
❌ Failed: 0
========================================

✅ All smoke tests PASSED
```

## Technical Notes

### Role Hashes

For reference, the role hashes used:

```javascript
ROLE_KASU_ADMIN = 0x0000000000000000000000000000000000000000000000000000000000000000
ROLE_PROTOCOL_FEE_CLAIMER = keccak256("ROLE_PROTOCOL_FEE_CLAIMER")
ROLE_LENDING_POOL_CREATOR = keccak256("ROLE_LENDING_POOL_CREATOR")
ROLE_LENDING_POOL_FACTORY = keccak256("ROLE_LENDING_POOL_FACTORY")
```

### Access Control

To grant roles on Plume:

```bash
# Connect to KasuController
cast send 0x7923837dC93d897E12696e0F4FD50b51FBacf693 \
  "grantRole(bytes32,address)" \
  <ROLE_HASH> \
  <ADDRESS> \
  --rpc-url https://rpc.plume.org \
  --private-key $PRIVATE_KEY
```

Or use a multisig transaction via Safe UI.

## Resources

- **Plume Explorer:** https://explorer.plume.org
- **Plume RPC:** https://rpc.plume.org
- **Chain Config:** `scripts/_config/chains.ts`
- **Deployment Addresses:** `.openzeppelin/plume-addresses.json`
- **Smoke Test Docs:** `scripts/smokeTests/README.md`
