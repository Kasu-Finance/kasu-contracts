# Blockscout Support for Deployment Validation

The `validateDeployment.ts` script now supports both Etherscan and Blockscout block explorers.

## Overview

Block explorers use different APIs:
- **Etherscan** (Base, XDC, etc.): Uses Etherscan API format (`/api?module=contract&action=getsourcecode`)
- **Blockscout** (Plume, etc.): Uses Blockscout v2 API format (`/api/v2/addresses/{address}`)

The script automatically detects which API format to use based on the URL pattern.

## How It Works

### Detection

The script checks if the API URL contains `/api/v2` to detect Blockscout:

```typescript
function isBlockscoutApi(apiUrl: string): boolean {
    return apiUrl.includes('/api/v2');
}
```

### Blockscout API Endpoints

1. **Check verification status**: `/api/v2/addresses/{address}`
   ```json
   {
     "is_verified": true,
     "name": "KasuController"
   }
   ```

2. **Get source code**: `/api/v2/smart-contracts/{address}`
   ```json
   {
     "name": "KasuController",
     "source_code": "pragma solidity...",
     "additional_sources": [
       {
         "file_path": "contracts/Ownable.sol",
         "source_code": "pragma solidity..."
       }
     ]
   }
   ```

### No API Key Required

Unlike Etherscan, Blockscout explorers typically don't require API keys:
- Set `PLUME_SCAN_API_KEY=''` (empty string) in hardhat.config.ts
- The script will work without authentication

## Configuration

In `hardhat.config.ts`:

```typescript
etherscan: {
    apiKey: {
        plume: process.env.PLUME_SCAN_API_KEY ?? '', // Empty string is fine
    },
    customChains: [
        {
            network: 'plume',
            chainId: 98866,
            urls: {
                apiURL: 'https://explorer.plume.org/api/v2', // Blockscout v2 API
                browserURL: 'https://explorer.plume.org/',
            },
        },
    ],
}
```

## Usage

### Validate Deployment on Blockscout Explorer

```bash
# Plume (Blockscout)
DEPLOYMENT_MODE=lite AUTO_VERIFY=false npx hardhat --network plume run scripts/admin/validateDeployment.ts

# Base (Etherscan)
DEPLOYMENT_MODE=full AUTO_VERIFY=false npx hardhat --network base run scripts/admin/validateDeployment.ts
```

### Output

```
Network: plume | Mode: lite | Explorer: explorer.plume.org

Checking 19 contracts...

============================================================

OK (source matches & verified): 11
  ✓ KasuController
  ✓ LendingPoolManager
  ...

SOURCE MISMATCH: 7
  ✗ KSULocking (KSULockingLite) (can upgrade)
  ✗ SystemVariables (can upgrade)
  ...

============================================================
Summary: 11 OK, 7 source mismatch, 0 not verified, 1 unknown
```

## Source Code Comparison

The script compares on-chain source code with local source files:

1. **Fetches verified source** from explorer (Etherscan or Blockscout)
2. **Finds local source** in `src/` directory
3. **Normalizes both** (removes whitespace differences)
4. **Compares** and reports match/mismatch

### Results

- **✓ OK**: Source code matches exactly
- **✗ SOURCE MISMATCH**: On-chain differs from local (needs upgrade if proxy)
- **? NOT VERIFIED**: Contract not verified on explorer
- **? UNKNOWN**: Verified but local source not found

## Adding New Blockscout Networks

To add support for a new network using Blockscout:

1. Add to `hardhat.config.ts` customChains:
   ```typescript
   {
       network: 'newchain',
       chainId: 12345,
       urls: {
           apiURL: 'https://explorer.newchain.com/api/v2',  // Must end in /api/v2
           browserURL: 'https://explorer.newchain.com/',
       },
   }
   ```

2. Add network to `networks` section:
   ```typescript
   newchain: {
       url: process.env.NEWCHAIN_RPC_URL ?? 'https://rpc.newchain.com',
       chainId: 12345,
   }
   ```

3. Add to chain config (`scripts/_config/chains.ts`):
   ```typescript
   newchain: {
       name: 'NewChain',
       chainId: 12345,
       wrappedNativeAddress: '0x...',
       usdcAddress: '0x...',
       // ... other config
   }
   ```

4. Run validation:
   ```bash
   DEPLOYMENT_MODE=lite npx hardhat --network newchain run scripts/admin/validateDeployment.ts
   ```

## Limitations

### Auto-Verification

The `AUTO_VERIFY=true` feature only works with Etherscan-compatible explorers. Blockscout has a different verification API that is not yet supported.

For Blockscout explorers:
- Contracts must be verified manually or during deployment
- Set `AUTO_VERIFY=false` to skip verification attempts
- The script will still check if contracts are already verified

### Rate Limiting

- **Etherscan**: Rate limits apply (requires API key for higher limits)
- **Blockscout**: No rate limiting (free, no API key required)

The script includes a 200ms delay between requests to avoid rate limiting on Etherscan.

## Troubleshooting

### "Not Verified" when contracts are verified

Check that the API URL is correct in `hardhat.config.ts`. For Blockscout explorers, it must end with `/api/v2`.

### "Source Mismatch" for correct contracts

This usually means:
1. The on-chain contract is an older version (needs upgrade)
2. Or the local source has unreleased changes

Check the deployment date vs the last commit date to determine which case applies.

### "Local source not found"

The script searches `src/` recursively. Ensure:
1. Contract file exists in `src/` subdirectories
2. Filename matches contract name exactly (e.g., `KasuController.sol`)
3. For Lite contracts, ensure the export name mapping is correct in `getContractName()`

## Examples

### Plume (Blockscout)

```bash
# Validate Plume deployment
DEPLOYMENT_MODE=lite AUTO_VERIFY=false npx hardhat --network plume run scripts/admin/validateDeployment.ts

# Results show which contracts need upgrades
# Upgrade mismatched contracts
DEPLOYMENT_MODE=lite DEPLOY_UPDATES=true npx hardhat --network plume deploy

# Validate again to confirm all match
DEPLOYMENT_MODE=lite AUTO_VERIFY=false npx hardhat --network plume run scripts/admin/validateDeployment.ts
```

### Base (Etherscan)

```bash
# Validate Base deployment (requires ETHERSCAN_API_KEY)
DEPLOYMENT_MODE=full AUTO_VERIFY=false npx hardhat --network base run scripts/admin/validateDeployment.ts
```

## Related Documentation

- Smoke Tests: `scripts/smokeTests/README.md`
- Plume Results: `scripts/smokeTests/PLUME_RESULTS.md`
- Chain Configuration: `scripts/_config/chains.ts`
