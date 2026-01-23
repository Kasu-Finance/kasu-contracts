# Kasu Protocol Role Assignment Reference

This document outlines the complete role assignment structure for Kasu deployments.

## Role Overview

| Role | Assigned To | Purpose |
|------|-------------|---------|
| `ROLE_KASU_ADMIN` | Kasu Multisig | System-wide admin role, can grant/revoke all other roles |
| `ROLE_LENDING_POOL_FACTORY` | LendingPoolFactory Contract | Can create new lending pools |
| `ROLE_LENDING_POOL_CREATOR` | Pool Admin Multisig | Can initiate pool creation via LendingPoolManager |
| `ROLE_POOL_ADMIN` | Pool Admin Multisig | Can manage pool-level roles |
| `ROLE_POOL_MANAGER` | Pool Manager Multisig | Can manage pool settings and operations |
| `ROLE_POOL_FUNDS_MANAGER` | Pool Manager Multisig | Can manage pool funds (draw, repay) |
| `ROLE_POOL_CLEARING_MANAGER` | Pool Admin Multisig | Can execute clearing for pools |
| `ROLE_PROTOCOL_FEE_CLAIMER` | TBD per deployment | Can claim accrued protocol fees |

## Multisig Addresses

### Base Mainnet

| Multisig | Address | Roles |
|----------|---------|-------|
| Kasu Multisig | `0xC3128d734563E0d034d3ea177129657408C09D35` | ROLE_KASU_ADMIN<br>Proxy ownership<br>Beacon ownership |
| Pool Manager | `0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2` | ROLE_POOL_MANAGER<br>ROLE_POOL_FUNDS_MANAGER |
| Pool Admin | `0x7adf999af5E0617257014C94888cf98c4584E5E9` | ROLE_LENDING_POOL_CREATOR<br>ROLE_POOL_ADMIN<br>ROLE_POOL_CLEARING_MANAGER |

### Plume Mainnet

| Multisig | Address | Roles |
|----------|---------|-------|
| Kasu Multisig | `0x344BA98De46750e0B7CcEa8c3922Db8A70391189` | ROLE_KASU_ADMIN<br>Proxy ownership<br>Beacon ownership |
| Pool Manager | `0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe` | ROLE_POOL_MANAGER<br>ROLE_POOL_FUNDS_MANAGER |
| Pool Admin | `0xEb8D4618713517C1367aCA4840b1fca3d8b090DF` | ROLE_LENDING_POOL_CREATOR<br>ROLE_POOL_ADMIN<br>ROLE_POOL_CLEARING_MANAGER |

### XDC Mainnet

| Multisig | Address | Roles |
|----------|---------|-------|
| Kasu Multisig | `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D` | ROLE_KASU_ADMIN<br>Proxy ownership<br>Beacon ownership |
| Pool Manager | _Not set yet_ | ROLE_POOL_MANAGER<br>ROLE_POOL_FUNDS_MANAGER |
| Pool Admin | _Not set yet_ | ROLE_LENDING_POOL_CREATOR<br>ROLE_POOL_ADMIN<br>ROLE_POOL_CLEARING_MANAGER |

## Role Hierarchy

```
ROLE_KASU_ADMIN (Kasu Multisig)
├── Can grant/revoke all roles
├── Controls system pause/unpause
├── Owns all ProxyAdmin contracts
└── Owns all Beacon contracts

ROLE_LENDING_POOL_FACTORY (LendingPoolFactory Contract)
└── Automatically set during pool creation to grant pool roles

ROLE_LENDING_POOL_CREATOR (Pool Admin Multisig)
├── Can call lendingPoolManager.createPool()
└── Initiates new pool deployment

ROLE_POOL_ADMIN (Pool Admin Multisig)
├── Can grant/revoke pool-specific roles
└── Manages pool-level access control

ROLE_POOL_MANAGER (Pool Manager Multisig)
├── Can update pool settings (desired draw amount, etc.)
├── Can stop/pause pool operations
└── General pool administration

ROLE_POOL_FUNDS_MANAGER (Pool Manager Multisig)
├── Can draw funds from pool
├── Can repay owed funds to pool
└── Manages pool liquidity

ROLE_POOL_CLEARING_MANAGER (Pool Admin Multisig)
├── Can execute clearing operations
├── Can start clearing periods
└── Processes deposit/withdrawal requests

ROLE_PROTOCOL_FEE_CLAIMER (Configured per deployment)
├── Can claim protocol fees
└── Typically assigned to treasury or fee receiver address
```

## Contract Ownership

### ProxyAdmin Contracts
- Each TransparentProxy has its own ProxyAdmin
- All ProxyAdmins must be owned by Kasu Multisig
- Allows secure upgrades via multisig approval

### Beacon Contracts
- Shared upgradeable implementation for BeaconProxy instances
- All Beacons must be owned by Kasu Multisig
- Single upgrade affects all proxies using that beacon

## Global vs Pool-Specific Roles

### Global Roles
These roles are assigned at the system level (on KasuController directly):
- `ROLE_KASU_ADMIN`
- `ROLE_LENDING_POOL_FACTORY`
- `ROLE_LENDING_POOL_CREATOR`
- `ROLE_PROTOCOL_FEE_CLAIMER`

Validated by: `validateDeploymentComplete.ts`

### Pool-Specific Roles
These roles are scoped to individual lending pools (using `hasLendingPoolRole`):
- `ROLE_POOL_ADMIN`
- `ROLE_POOL_MANAGER`
- `ROLE_POOL_FUNDS_MANAGER`
- `ROLE_POOL_CLEARING_MANAGER`

Validated by: `validatePoolRoles.ts` (requires pool addresses)

## Security Considerations

1. **Deployer Account**: After deployment, the deployer account MUST NOT retain any roles:
   - ❌ Must NOT have ROLE_KASU_ADMIN
   - ❌ Must NOT own any ProxyAdmin contracts
   - ❌ Must NOT own any Beacon contracts

2. **Multisig Separation**: Three distinct multisigs provide separation of concerns:
   - **Kasu Multisig**: System-level control (upgrades, admin roles)
   - **Pool Manager**: Operational control (funds management, pool settings)
   - **Pool Admin**: Pool lifecycle (creation, clearing, pool-level roles)

3. **Role Validation**: Use smoke tests to verify correct role assignment:
   ```bash
   # Validate global roles and ownership
   npx hardhat --network <network> run scripts/smokeTests/validateDeploymentComplete.ts

   # Validate pool-specific roles
   LENDING_POOL_ADDRESSES=0xpool1,0xpool2 \
     npx hardhat --network <network> run scripts/smokeTests/validatePoolRoles.ts
   ```

## Granting Roles

Roles are granted via `KasuController.grantRole()`:

```solidity
// Example: Grant ROLE_POOL_MANAGER to pool manager multisig
kasuController.grantRole(ROLE_POOL_MANAGER, poolManagerMultisig);
```

Only accounts with ROLE_KASU_ADMIN can grant these global roles.

## Revoking Roles

Roles are revoked via `KasuController.revokeRole()`:

```solidity
// Example: Revoke ROLE_KASU_ADMIN from deployer
kasuController.revokeRole(ROLE_KASU_ADMIN, deployerAddress);
```

## Environment Configuration

Set multisig addresses in `scripts/_env/.{network}.env`:

```bash
# Kasu multisig (proxy ownership & ROLE_KASU_ADMIN)
KASU_MULTISIG=0xC3128d734563E0d034d3ea177129657408C09D35

# Pool manager multisig (ROLE_POOL_MANAGER, ROLE_POOL_FUNDS_MANAGER)
POOL_MANAGER_MULTISIG=0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2

# Pool admin multisig (ROLE_LENDING_POOL_CREATOR, ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER)
POOL_ADMIN_MULTISIG=0x7adf999af5E0617257014C94888cf98c4584E5E9
```

Or set in `scripts/_config/chains.ts` for permanent network configuration.
