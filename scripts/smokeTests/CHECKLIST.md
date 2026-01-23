# Post-Deployment Checklist

Use this checklist after deploying Kasu contracts to ensure proper configuration.

## 1. Run Smoke Tests

```bash
# Complete validation (recommended)
npx hardhat --network <network> run scripts/smokeTests/validateDeploymentComplete.ts

# Quick role & ownership check
npx hardhat --network <network> run scripts/smokeTests/validateRolesAndOwnership.ts
```

## 2. Review Results

The smoke tests will validate:

### ✅ Ownership & Security
- [ ] All ProxyAdmin contracts owned by Kasu multisig (not deployer)
- [ ] All Beacon contracts owned by Kasu multisig (not deployer)
- [ ] Deployer does NOT have ROLE_KASU_ADMIN

### ✅ Role Configuration
- [ ] Kasu multisig has ROLE_KASU_ADMIN
- [ ] LendingPoolFactory has ROLE_LENDING_POOL_FACTORY
- [ ] Pool admin multisig has ROLE_LENDING_POOL_CREATOR
- [ ] Pool admin multisig has ROLE_POOL_ADMIN
- [ ] Pool admin multisig has ROLE_POOL_CLEARING_MANAGER
- [ ] Pool manager multisig has ROLE_POOL_MANAGER
- [ ] Pool manager multisig has ROLE_POOL_FUNDS_MANAGER
- [ ] ROLE_PROTOCOL_FEE_CLAIMER is assigned

### ✅ Protocol Configuration
- [ ] protocolFeeReceiver is set and is not deployer

## 3. Manual Verification

After automated tests pass, manually verify:

### Network Explorer
- [ ] All implementation contracts are verified on block explorer
- [ ] Multisig contract is accessible and has correct signers

### KasuController Roles
```bash
# View all proxy admins
npx hardhat --network <network> run scripts/admin/printProxyAdmins.ts
```

Expected:
- All ProxyAdmin owners should be the Kasu multisig
- No ProxyAdmin should be owned by deployer account

## 4. Optional: Transfer Ownership

If ProxyAdmins are still owned by deployer:

```bash
NEW_PROXY_ADMIN_OWNER=0x<MULTISIG_ADDRESS> \
  npx hardhat --network <network> run scripts/admin/transferAllProxyAdminOwnership.ts
```

## 5. Contract Verification

Validate bytecode matches source:

```bash
# Check all contracts
DEPLOYMENT_MODE=<full|lite> \
  npx hardhat --network <network> run scripts/admin/validateDeployment.ts

# Auto-verify unverified contracts
DEPLOYMENT_MODE=<full|lite> AUTO_VERIFY=true \
  npx hardhat --network <network> run scripts/admin/validateDeployment.ts
```

## Network-Specific Information

### Base Mainnet
- Network: `base`
- Deployment mode: `full`
- Kasu Multisig: `0xC3128d734563E0d034d3ea177129657408C09D35`
- Pool Manager Multisig: `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2`
- Pool Admin Multisig: `0x7adf999af5E0617257014C94888cf98c4584E5E9`

### Plume Mainnet
- Network: `plume`
- Deployment mode: `lite`
- Kasu Multisig: `0x344BA98De46750e0B7CcEa8c3922Db8A70391189`
- Pool Manager Multisig: `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe`
- Pool Admin Multisig: `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF`

### XDC Mainnet
- Network: `xdc`
- Deployment mode: `full` or `lite`
- Kasu Multisig: `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D`
- Pool Manager Multisig: _Not set yet_
- Pool Admin Multisig: _Not set yet_

## Troubleshooting

### "ProxyAdmin still owned by deployer"
Run the transferAllProxyAdminOwnership script (see step 4).

### "Multisig does NOT have ROLE_KASU_ADMIN"
From the admin account, call:
```solidity
kasuController.grantRole(ROLE_KASU_ADMIN, <multisig_address>)
```

### "Deployer still has admin role"
From the multisig or an admin account, call:
```solidity
kasuController.revokeRole(ROLE_KASU_ADMIN, <deployer_address>)
```

### "ROLE_PROTOCOL_FEE_CLAIMER not set"
From an admin account, call:
```solidity
kasuController.grantRole(ROLE_PROTOCOL_FEE_CLAIMER, <fee_claimer_address>)
```

### "protocolFeeReceiver not set or is deployer"
From an admin account, call:
```solidity
systemVariables.setProtocolFeeReceiver(<fee_receiver_address>)
```
