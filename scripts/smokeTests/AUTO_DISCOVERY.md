# Automatic Pool Discovery

The smoke test scripts automatically discover all lending pools by querying `PoolCreated` events from the `LendingPoolFactory` contract.

## How It Works

1. **RPC Query**: Scripts query `PoolCreated` events via your configured RPC provider
2. **Extract Addresses**: Pool addresses are extracted from event data
3. **Validate Roles**: For each discovered pool, validate pool-specific roles

## Requirements

**Archive Node Access Required**

The default public RPC endpoints (e.g., `https://mainnet.base.org`) don't support historical event queries. You need an RPC provider with archive node access:

### Option 1: Alchemy (Recommended)
- Sign up: https://dashboard.alchemy.com
- Create Base app
- Free tier: 300M compute units/month
- Set `BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY`

### Option 2: Infura
- Sign up: https://infura.io
- Create Base project
- Free tier: 100k requests/day
- Set `BASE_RPC_URL=https://base-mainnet.infura.io/v3/YOUR_KEY`

### Option 3: Other Providers
- QuickNode: https://quicknode.com
- Ankr: https://www.ankr.com
- Any provider with archive access

## Benefits

✅ **No Manual Tracking**: Don't need to maintain a list of pool addresses
✅ **Always Up-to-Date**: Automatically includes newly created pools
✅ **Less Error-Prone**: No risk of typos or missing pools
✅ **Simpler Usage**: Just run `npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts`

## Usage

### Automatic Discovery (Default)

Simply run the script - it discovers pools automatically:

```bash
npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

Output:
```
📋 Auto-discovering lending pools from PoolCreated events...

  Found 3 lending pool(s)

📋 Validating Pool-Specific Roles for 3 pool(s)...

  Pool: 0xABC123...
  Pool: 0xDEF456...
  Pool: 0x789GHI...
```

### Manual Override

If auto-discovery fails (e.g., RPC doesn't support event logs), specify pools manually:

```bash
LENDING_POOL_ADDRESSES=0xpool1,0xpool2,0xpool3 \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

## Configuration

Add to `scripts/_env/.env`:

```bash
# For Base mainnet
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY

# Or for Base Sepolia
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY
```

Then add to `hardhat.config.ts` (already configured):
```typescript
base: {
    url: process.env.BASE_RPC_URL || 'https://mainnet.base.org',
    chainId: 8453,
}
```

## When Auto-Discovery May Fail

Auto-discovery will fail if:

1. **No Archive Access**: RPC provider doesn't support historical event queries
2. **Rate Limits**: Free tier RPC limits exceeded
3. **No Pools Created**: No `PoolCreated` events exist yet

## Solutions for Discovery Issues

### 1. Use Paginated Discovery (Built-in)

The module includes `discoverPoolAddressesPaginated()` for chains with strict rate limits:

```typescript
import { discoverPoolAddressesPaginated } from './_modules/poolDiscovery';

const pools = await discoverPoolAddressesPaginated(
    factoryAddress,
    0,        // fromBlock
    10000,    // blocks per query
);
```

### 2. Manual Specification

Set `LENDING_POOL_ADDRESSES` environment variable:

```bash
LENDING_POOL_ADDRESSES=0xpool1,0xpool2,0xpool3 \
  npx hardhat --network base run scripts/smokeTests/validateDeploymentComplete.ts
```

### 3. Use Archive RPC

Configure hardhat.config.ts with an archive node RPC endpoint:

```typescript
base: {
    url: "https://base-mainnet.archive.infura.io/v3/YOUR_KEY",
    // ...
}
```

### 4. Tenderly Integration (Future)

For better event querying and transaction simulation, integrate Tenderly API:
- More reliable event queries
- Transaction simulation for role grant operations
- Better debugging for failed validations

## Implementation Details

### Core Module: `_modules/poolDiscovery.ts`

```typescript
export async function discoverPoolAddresses(
    lendingPoolFactoryAddress: string,
    fromBlock: number = 0,
): Promise<string[]>
```

**How it works:**
1. Connects to LendingPoolFactory contract
2. Creates event filter for `PoolCreated`
3. Queries events from `fromBlock` to latest
4. Extracts unique pool addresses
5. Returns array of pool addresses

### Fallback Behavior

If auto-discovery fails:
1. Script logs a warning message
2. Suggests using `LENDING_POOL_ADDRESSES` for manual specification
3. Continues with global validation (skips pool validation)
4. **Does not fail the entire smoke test**

## Network Compatibility

| Network | Auto-Discovery | Notes |
|---------|---------------|-------|
| Base Mainnet | ✅ Yes | Works with standard RPC |
| Base Sepolia | ✅ Yes | Works with standard RPC |
| Plume | ✅ Yes | Works with standard RPC |
| XDC | ⚠️  Depends | May need archive node |
| Localhost | ✅ Yes | Full event history available |

## Future Enhancements

### Tenderly Integration

```typescript
// Future: Query events via Tenderly API
import { TenderlyClient } from './tenderly';

const client = new TenderlyClient(process.env.TENDERLY_API_KEY);
const pools = await client.queryPoolCreatedEvents(factoryAddress);
```

Benefits:
- No RPC rate limits
- Fast event queries
- Transaction simulation
- Historical data always available

### Caching

```typescript
// Future: Cache discovered pools
const cache = new PoolCache('./.pool-cache.json');
const pools = await cache.getOrDiscover(factoryAddress);
```

### Multi-Factory Support

```typescript
// Future: Support multiple factory contracts
const pools = await discoverPoolsFromFactories([
    factory1Address,
    factory2Address,
]);
```

## Testing

Test auto-discovery locally:

```bash
# Start local node
npm run node:local

# Deploy contracts and create pools
npm run scripts:deploy
npm run scripts:createTestLendingPools

# Run smoke tests (should auto-discover the test pools)
npx hardhat --network localhost run scripts/smokeTests/validateDeploymentComplete.ts
```

Expected output:
```
📋 Auto-discovering lending pools from PoolCreated events...

  Found 4 lending pool(s)

📋 Validating Pool-Specific Roles for 4 pool(s)...
```
