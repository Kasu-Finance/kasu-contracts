import {
    grantLendingPoolRole,
    ROLE_POOL_ADMIN,
    ROLE_POOL_MANAGER,
    ROLE_POOL_CLEARING_MANAGER,
    ROLE_POOL_FUNDS_MANAGER,
} from '../_modules/grantLendingPoolRole';
import { getAccounts } from '../_modules/getAccounts';
import { getChainConfig } from '../_config/chains';
import * as hre from 'hardhat';

/**
 * Grants all pool-specific roles to the configured multisigs for all pools.
 *
 * Pool Admin Multisig receives:
 * - ROLE_POOL_ADMIN
 * - ROLE_POOL_CLEARING_MANAGER
 *
 * Pool Manager Multisig receives:
 * - ROLE_POOL_MANAGER
 * - ROLE_POOL_FUNDS_MANAGER
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/lendingPools/grantAllPoolRoles.ts
 *
 * Pools are read from chains.ts config or LENDING_POOL_ADDRESSES env variable.
 */
export async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);

    const { poolAdminMultisig, poolManagerMultisig, lendingPoolAddresses } = chainConfig;

    if (!poolAdminMultisig) {
        throw new Error(`poolAdminMultisig not configured for network ${networkName}`);
    }
    if (!poolManagerMultisig) {
        throw new Error(`poolManagerMultisig not configured for network ${networkName}`);
    }
    if (lendingPoolAddresses.length === 0) {
        throw new Error(
            `No lending pools configured for network ${networkName}. ` +
            `Set LENDING_POOL_ADDRESSES env or add to chains.ts.`
        );
    }

    console.log('========================================');
    console.log('Grant All Pool Roles');
    console.log('========================================');
    console.log(`Network: ${chainConfig.name} (${networkName})`);
    console.log(`Pool Admin Multisig: ${poolAdminMultisig}`);
    console.log(`Pool Manager Multisig: ${poolManagerMultisig}`);
    console.log(`Pools: ${lendingPoolAddresses.length}`);
    console.log('========================================\n');

    const signers = await getAccounts(networkName);
    const adminAccount = signers[1];
    const adminAddress = await adminAccount.getAddress();
    console.log(`Signer (admin): ${adminAddress}\n`);

    // Note: ROLE_POOL_ADMIN is granted automatically during pool creation by LendingPoolFactory
    // Only grant the additional roles needed for pool operations
    const rolesToGrant = [
        { role: ROLE_POOL_CLEARING_MANAGER, roleName: 'ROLE_POOL_CLEARING_MANAGER', recipient: poolAdminMultisig },
        { role: ROLE_POOL_MANAGER, roleName: 'ROLE_POOL_MANAGER', recipient: poolManagerMultisig },
        { role: ROLE_POOL_FUNDS_MANAGER, roleName: 'ROLE_POOL_FUNDS_MANAGER', recipient: poolManagerMultisig },
    ];

    let successCount = 0;
    let errorCount = 0;

    for (const poolAddress of lendingPoolAddresses) {
        console.log(`\nPool: ${poolAddress}`);
        console.log('-'.repeat(50));

        for (const { role, roleName, recipient } of rolesToGrant) {
            try {
                console.log(`  Granting ${roleName} to ${recipient}...`);
                await grantLendingPoolRole(poolAddress, recipient, role, adminAccount);
                console.log(`  ✅ ${roleName} granted`);
                successCount++;
            } catch (error: any) {
                console.error(`  ❌ Failed to grant ${roleName}: ${error.message}`);
                errorCount++;
            }
        }
    }

    console.log('\n========================================');
    console.log('Summary');
    console.log('========================================');
    console.log(`Total transactions: ${successCount + errorCount}`);
    console.log(`✅ Successful: ${successCount}`);
    console.log(`❌ Failed: ${errorCount}`);
    console.log('========================================');

    if (errorCount > 0) {
        process.exitCode = 1;
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
