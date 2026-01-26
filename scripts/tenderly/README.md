# Tenderly Simulations

This directory contains scripts for simulating transactions on deployed networks using Tenderly's Simulation API.

## Overview

Tenderly simulations allow you to test transactions before executing them on-chain. This is particularly useful for:
- Testing complex transactions on production networks without risking funds
- Verifying role-based access control works correctly
- Debugging transaction failures
- Estimating gas costs accurately

**Integration with Smoke Tests**: The pool creation simulation is automatically run as part of `scripts/smokeTests/validateDeploymentComplete.ts`. If Tenderly credentials are not configured, the simulation is gracefully skipped. You can also run simulations standalone using the scripts in this directory.

## Prerequisites

1. **Tenderly Account**: Sign up at [dashboard.tenderly.co](https://dashboard.tenderly.co)

2. **Access Key**: Generate an access key at [dashboard.tenderly.co/account/authorization](https://dashboard.tenderly.co/account/authorization)

3. **Environment Variables**:
   ```bash
   # Required
   TENDERLY_ACCESS_KEY=your_access_key_here
   TENDERLY_ACCOUNT_ID=your_username_or_org_slug
   TENDERLY_PROJECT_SLUG=your_project_slug
   ```

   Add these to your `scripts/_env/.env` file or export them in your shell.

## Available Simulations

### `simulateCreatePool.ts`

Simulates `lendingPoolManager.createPool()` calls to verify pool creation works with the LENDING_POOL_CREATOR role.

**Tests**:
- Pool creation with correct role assignment
- Works in both Full (Base) and Lite (Plume) deployments
- Validates transaction succeeds before on-chain execution

**Usage**:
```bash
# Simulate on Base (Full deployment)
TENDERLY_ACCESS_KEY=... \
TENDERLY_ACCOUNT_ID=... \
TENDERLY_PROJECT_SLUG=... \
npx hardhat run --network base scripts/tenderly/simulateCreatePool.ts

# Simulate on Plume (Lite deployment)
TENDERLY_ACCESS_KEY=... \
TENDERLY_ACCOUNT_ID=... \
TENDERLY_PROJECT_SLUG=... \
npx hardhat run --network plume scripts/tenderly/simulateCreatePool.ts
```

**What it does**:
1. Loads deployment addresses for the specified network
2. Gets the pool admin multisig address (should have LENDING_POOL_CREATOR role)
3. Creates a test pool configuration
4. Encodes the `createPool` transaction
5. Simulates the transaction via Tenderly API
6. Reports success/failure and provides dashboard link

**Expected Output (Success)**:
```
========================================
Tenderly Pool Creation Simulation
========================================

Network: Base Mainnet (base)
Chain ID: 8453
Network ID for Tenderly: 8453

LendingPoolManager: 0x...
Pool Admin Multisig (LENDING_POOL_CREATOR): 0x7adf999af5E0617257014C94888cf98c4584E5E9

Pool Configuration:
  Name: Test Pool - Tenderly Simulation
  Symbol: TSIM
  Tranches: 2
  Tranche 0: 30% @ 30.00% APY
  Tranche 1: 70% @ 15.00% APY

📡 Simulating createPool transaction on Tenderly...
   From: 0x7adf999af5E0617257014C94888cf98c4584E5E9
   To: 0x...
   Calldata length: ... bytes

========================================
Simulation Result
========================================

✅ Simulation SUCCEEDED

Simulation ID: abc123...
Gas Used: 2500000
Block Number: 12345678

🔗 View in Tenderly Dashboard:
   https://dashboard.tenderly.co/your_account/your_project/simulator/abc123...

✅ Pool creation with LENDING_POOL_CREATOR role works on Base Mainnet!

========================================
```

## Tenderly Network IDs

The scripts use Tenderly's network IDs (which match chain IDs):

| Network | Chain ID | Tenderly Network ID |
|---------|----------|---------------------|
| Base Mainnet | 8453 | 8453 |
| Base Sepolia | 84532 | 84532 |
| Plume | 98866 | 98866 |
| XDC | 50 | 50 |

For additional networks, see [Tenderly's supported networks](https://docs.tenderly.co/supported-networks-and-languages).

## Troubleshooting

### "TENDERLY_ACCESS_KEY not set"
Generate an access key at [dashboard.tenderly.co/account/authorization](https://dashboard.tenderly.co/account/authorization) and export it:
```bash
export TENDERLY_ACCESS_KEY=your_key_here
```

### "TENDERLY_ACCOUNT_ID not set"
This is your Tenderly username or organization slug. Find it in your Tenderly dashboard URL:
```
https://dashboard.tenderly.co/YOUR_ACCOUNT_ID/your-project
                                  ^^^^^^^^^^^^^^^^
```

### "TENDERLY_PROJECT_SLUG not set"
This is your project slug. Find it in your Tenderly dashboard URL:
```
https://dashboard.tenderly.co/your-account/YOUR_PROJECT_SLUG
                                            ^^^^^^^^^^^^^^^^^^
```

### "Tenderly API error: 401"
Your access key is invalid or expired. Generate a new one.

### "Tenderly API error: 403"
Your Tenderly plan doesn't support simulations, or you've exceeded your quota.

### "Network not configured for Tenderly simulations"
Add the network to the `networkIds` map in the simulation script.

### Simulation fails with "AccessControlUnauthorizedAccount"
The address used in the simulation doesn't have the required role. Verify:
1. The correct multisig address is configured in `scripts/_config/chains.ts`
2. The multisig has LENDING_POOL_CREATOR role on-chain (check with smoke tests)

## Resources

- [Tenderly Documentation](https://docs.tenderly.co/)
- [Simulation API Reference](https://docs.tenderly.co/simulations-and-forks/simulation-api)
- [Supported Networks](https://docs.tenderly.co/supported-networks-and-languages)
- [Tenderly Dashboard](https://dashboard.tenderly.co/)

## Adding New Simulations

To add a new simulation:

1. Create a new script in this directory (e.g., `simulateUpgrade.ts`)
2. Follow the pattern in `simulateCreatePool.ts`:
   - Load deployment addresses
   - Get the caller address (with appropriate role)
   - Encode the transaction
   - Call `simulateTransaction()`
   - Report results
3. Document the simulation in this README
4. Test on testnets first before mainnet simulations

## Notes

- Simulations are saved to your Tenderly dashboard (if `save: true`)
- Failed simulations are also saved (if `save_if_fails: true`)
- Simulations don't cost gas or affect on-chain state
- Use simulations to test transactions before using multisigs on mainnet
