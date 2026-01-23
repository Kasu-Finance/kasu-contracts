import hre from 'hardhat';
import { LendingPoolFactory__factory } from '../../../typechain-types';

/**
 * Discovers all lending pool addresses by querying PoolCreated events
 * from the LendingPoolFactory contract.
 *
 * Note: For mainnet deployments, auto-discovery is not practical due to millions of blocks.
 * Use manual pool specification via LENDING_POOL_ADDRESSES env variable instead.
 */
export async function discoverPoolAddresses(
    lendingPoolFactoryAddress: string,
    fromBlock: number = 0,
): Promise<string[]> {
    // For mainnet deployments with millions of blocks, auto-discovery is not practical
    // with free tier RPC providers. Use manual specification instead.
    const currentBlock = await hre.ethers.provider.getBlockNumber();
    const blockRange = currentBlock - fromBlock;

    if (blockRange > 100000) {
        console.warn(`  ⚠️  Auto-discovery would need to scan ${blockRange.toLocaleString()} blocks`);
        console.warn(`  ⚠️  This is not practical with free tier RPC providers`);
        console.warn(`\n  💡 Please specify pool addresses manually:`);
        console.warn(`     LENDING_POOL_ADDRESSES=0xPool1,0xPool2,0xPool3`);
        return [];
    }

    const factory = LendingPoolFactory__factory.connect(
        lendingPoolFactoryAddress,
        hre.ethers.provider,
    );

    try {
        console.log(`  Querying PoolCreated events from block ${fromBlock} to ${currentBlock}...`);

        const filter = factory.filters.PoolCreated();
        const events = await factory.queryFilter(filter, fromBlock, currentBlock);

        const poolAddresses = events.map((event) => event.args.lendingPool);
        const uniquePools = [...new Set(poolAddresses)];

        if (uniquePools.length > 0) {
            console.log(`  ✅ Found ${uniquePools.length} pool(s)`);
        } else {
            console.log(`  ℹ️  No pools found`);
        }

        return uniquePools;
    } catch (error: any) {
        if (error.message?.includes('block range')) {
            console.warn(`  ⚠️  RPC provider block range limit exceeded`);
            console.warn(`\n  💡 Please specify pool addresses manually:`);
            console.warn(`     LENDING_POOL_ADDRESSES=0xPool1,0xPool2,0xPool3`);
        } else {
            console.warn(`  ⚠️  RPC event query failed: ${error.message}`);
        }
        return [];
    }
}
