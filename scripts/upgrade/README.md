# Contract Upgrade Scripts

Scripts for upgrading proxy contracts on production networks.

## Plume Upgrade (Feb 2026)

**Status: Implementations deployed, awaiting multisig execution**

7 contracts upgraded to sync with release-candidate codebase:

| Proxy | Old Implementation | New Implementation | Contract |
|-------|-------------------|-------------------|----------|
| 0xE768...052 | 0x5D9b...dBA | 0x6BAB...55f | KSULockingLite |
| 0x0B98...931 | 0xb0D7...868 | 0xe81D...904 | KsuPriceLite |
| 0xb829...DC6 | 0xB145...E1b | 0x990b...82bC | SystemVariables |
| 0x59E4...576 | 0x221a...1b | 0x7fF4...e81 | FixedTermDeposit |
| 0x193B...B69 | 0xaFb2...765 | 0xC7c8...aC0 | UserLoyaltyRewardsLite |
| 0xB478...635 | 0xF0e9...E9 | 0x666b...b52 | UserManagerLite |
| 0xE1Be...0B5 | 0xd281...229 | 0x1619...38 | ProtocolFeeManagerLite |

### Files

- `deployPlumeImplementations.ts` - Deploys new implementations and generates Gnosis Safe JSON
- `../multisig/plume-implementations.json` - Record of deployed implementation addresses
- `../multisig/plume-upgrade-all.json` - Gnosis Safe transaction batch (8 txs)

### Execute via Gnosis Safe

1. Go to Plume Safe Transaction Builder
2. Upload `scripts/multisig/plume-upgrade-all.json`
3. Review 8 transactions (7 upgrades + 1 revoke old admin)
4. Sign with required multisig members

### Verify After Execution

```bash
# Run smoke tests
npx hardhat --network plume run scripts/smokeTests/validateDeploymentComplete.ts

# Validate source code matches
npx hardhat --network plume run scripts/admin/validateDeployment.ts
```

## Creating Upgrades for Other Networks

To upgrade contracts on another network:

1. Copy and modify `deployPlumeImplementations.ts` for the target network
2. Update ProxyAdmin addresses (use `cast admin <proxy>`)
3. Run the script to deploy implementations and generate Gnosis Safe JSON
4. Execute via the network's Gnosis Safe
