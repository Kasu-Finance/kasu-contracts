import hre from 'hardhat';
import { getChainConfig } from '../_config/chains';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { validatePoolSpecificRoles, PoolValidationResult } from './_modules/poolRoleValidation';
import { discoverPoolAddresses } from './_modules/poolDiscovery';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

async function main() {
    const networkName = hre.network.name;
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);
    const chainConfig = getChainConfig(networkName);

    console.log('\n========================================');
    console.log('Kasu Pool-Specific Role Validation');
    console.log('========================================\n');

    console.log(`Network: ${chainConfig.name} (${networkName})`);
    console.log(`Block: ${blockNumber}\n`);

    const poolManagerMultisig = chainConfig.poolManagerMultisig;
    const poolAdminMultisig = chainConfig.poolAdminMultisig;

    if (poolManagerMultisig) {
        console.log(`Pool Manager Multisig: ${poolManagerMultisig}`);
    }
    if (poolAdminMultisig) {
        console.log(`Pool Admin Multisig: ${poolAdminMultisig}`);
    }

    // Get contract addresses first
    const addresses = addressFile.getContractAddresses() as Record<string, AddressEntry>;

    // Get pool addresses from chain config
    let poolAddresses: string[] = chainConfig.lendingPoolAddresses || [];

    if (poolAddresses.length > 0) {
        console.log(`\nUsing ${poolAddresses.length} pool address(es) from chain config...\n`);
    } else {
        // Try auto-discovery if no pools configured
        console.log('\n⚠️  No pool addresses configured in chains.ts');
        console.log('Attempting auto-discovery from PoolCreated events...\n');
        const lendingPoolFactory = addresses.LendingPoolFactory?.address;
        if (lendingPoolFactory) {
            try {
                poolAddresses = await discoverPoolAddresses(lendingPoolFactory);
                if (poolAddresses.length > 0) {
                    console.log(`Found ${poolAddresses.length} lending pool(s)\n`);
                    console.log('💡 Tip: Add these to scripts/_config/chains.ts for faster validation:\n');
                    console.log(`   lendingPoolAddresses: [`);
                    poolAddresses.forEach((addr) => console.log(`       '${addr}',`));
                    console.log(`   ]\n`);
                } else {
                    console.error('❌ No lending pools found');
                    console.log('\nPlease add pool addresses to scripts/_config/chains.ts:');
                    console.log(`   lendingPoolAddresses: ['0xPool1', '0xPool2']\n`);
                    process.exitCode = 1;
                    return;
                }
            } catch (error) {
                console.error(`❌ Error discovering pools: ${error}`);
                console.log('\nPlease add pool addresses to scripts/_config/chains.ts:');
                console.log(`   lendingPoolAddresses: ['0xPool1', '0xPool2']\n`);
                process.exitCode = 1;
                return;
            }
        } else {
            console.error('❌ LendingPoolFactory address not found in deployment file');
            process.exitCode = 1;
            return;
        }
    }

    // Get KasuController address
    const kasuControllerEntry = addresses.KasuController;
    if (!kasuControllerEntry || !kasuControllerEntry.address) {
        console.error('❌ KasuController not found in deployment file');
        process.exitCode = 1;
        return;
    }

    const allResults: PoolValidationResult[] = [];

    // Validate each pool
    for (const poolAddress of poolAddresses) {
        console.log(`📋 Validating pool: ${poolAddress}\n`);
        const poolResults = await validatePoolSpecificRoles(
            poolAddress,
            poolManagerMultisig,
            poolAdminMultisig,
            kasuControllerEntry.address,
        );
        allResults.push(...poolResults);

        // Display results for this pool
        poolResults.forEach((r) => {
            const icon = r.passed ? '✅' : '❌';
            console.log(`  ${icon} ${r.role}: ${r.message}`);
        });
        console.log();
    }

    // Summary
    const failedCount = allResults.filter((r) => !r.passed).length;
    const passedCount = allResults.filter((r) => r.passed).length;
    const totalChecks = poolAddresses.length * 4; // 4 roles per pool

    console.log('========================================');
    console.log('Summary');
    console.log('========================================');
    console.log(`Pools validated: ${poolAddresses.length}`);
    console.log(`Total checks: ${allResults.length}`);
    console.log(`✅ Passed: ${passedCount}`);
    console.log(`❌ Failed: ${failedCount}`);
    console.log('========================================\n');

    if (failedCount > 0) {
        console.error('❌ Pool role validation FAILED');
        console.log('\nTo grant missing roles, use:');
        console.log('  kasuController.grantLendingPoolRole(poolAddress, role, multisigAddress)\n');
        process.exitCode = 1;
    } else {
        console.log('✅ All pool role validations PASSED');
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
