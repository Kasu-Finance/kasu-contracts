import hre from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getChainConfig } from '../_config/chains';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../../typechain-types/src/core/lendingPool/LendingPool';
import { LendingPoolManager__factory } from '../../typechain-types';

/**
 * Tenderly Simulation Module: Create Lending Pool
 *
 * This module provides functions to simulate createPool() calls on deployed networks
 * using Tenderly's API. It verifies that pool creation works correctly with the
 * LENDING_POOL_CREATOR role in both Full (Base) and Lite (Plume) deployments.
 *
 * Used by:
 * - scripts/smokeTests/validateDeploymentComplete.ts (optional validation step)
 * - scripts/tenderly/simulateCreatePool.ts (standalone testing)
 *
 * For more info on Tenderly simulations:
 * https://docs.tenderly.co/simulations-and-forks/simulation-api
 */

export interface TenderlySimulationResult {
    simulation: {
        id: string;
        status: boolean;
        gasUsed: string;
        blockNumber: string;
    };
    transaction: {
        hash: string;
        from: string;
        to: string;
        status: boolean;
        error_message?: string;
    };
}

export interface TenderlySimulationSummary {
    success: boolean;
    simulationId?: string;
    gasUsed?: string;
    dashboardUrl?: string;
    errorMessage?: string;
    skipped?: boolean;
    skipReason?: string;
}

export async function simulateTransaction(
    networkId: string,
    from: string,
    to: string,
    input: string,
): Promise<TenderlySimulationResult> {
    const TENDERLY_ACCESS_KEY = process.env.TENDERLY_ACCESS_KEY;
    const TENDERLY_ACCOUNT_ID = process.env.TENDERLY_ACCOUNT_ID;
    const TENDERLY_PROJECT_SLUG = process.env.TENDERLY_PROJECT_SLUG;

    if (!TENDERLY_ACCESS_KEY) {
        throw new Error(
            'TENDERLY_ACCESS_KEY not set. Get your access key from https://dashboard.tenderly.co/account/authorization'
        );
    }

    if (!TENDERLY_ACCOUNT_ID) {
        throw new Error(
            'TENDERLY_ACCOUNT_ID not set. This is your Tenderly username or organization slug.'
        );
    }

    if (!TENDERLY_PROJECT_SLUG) {
        throw new Error(
            'TENDERLY_PROJECT_SLUG not set. This is your project slug in Tenderly.'
        );
    }

    const simulationUrl = `https://api.tenderly.co/api/v1/account/${TENDERLY_ACCOUNT_ID}/project/${TENDERLY_PROJECT_SLUG}/simulate`;

    const body = {
        network_id: networkId,
        from,
        to,
        input,
        save: true, // Save simulation to Tenderly dashboard
        save_if_fails: true,
    };

    const response = await fetch(simulationUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-Access-Key': TENDERLY_ACCESS_KEY,
        },
        body: JSON.stringify(body),
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Tenderly API error: ${response.status} ${errorText}`);
    }

    return (await response.json()) as TenderlySimulationResult;
}

export function getNetworkId(networkName: string): string {
    // Tenderly network IDs - see https://docs.tenderly.co/supported-networks-and-languages
    const networkIds: Record<string, string> = {
        base: '8453',
        'base-sepolia': '84532',
        plume: '98866',
        xdc: '50',
    };

    const networkId = networkIds[networkName];
    if (!networkId) {
        throw new Error(
            `Network ${networkName} not configured for Tenderly simulations. ` +
                `Add it to the networkIds map in this script.`
        );
    }

    return networkId;
}

export function getDefaultPoolConfig(poolAdminAddress: string): CreatePoolConfigStruct {
    // Default pool configuration for testing
    const createTranchesConfig: CreateTrancheConfigStruct[] = [
        {
            ratio: 30_00, // 30%
            interestRate: 5_040_862_203_635_605n, // 30% APY
            minDepositAmount: 50_000_000n, // 50 USDC
            maxDepositAmount: 1_000_000_000_000n, // 1M USDC
        },
        {
            ratio: 70_00, // 70%
            interestRate: 2_682_121_951_395_655n, // 15% APY
            minDepositAmount: 50_000_000n, // 50 USDC
            maxDepositAmount: 2_000_000_000_000n, // 2M USDC
        },
    ];

    return {
        poolName: 'Test Pool - Tenderly Simulation',
        poolSymbol: 'TSIM',
        targetExcessLiquidityPercentage: 10_00n,
        minExcessLiquidityPercentage: 0n,
        tranches: createTranchesConfig,
        poolAdmin: poolAdminAddress,
        drawRecipient: poolAdminAddress,
        desiredDrawAmount: 0n,
    };
}

/**
 * Simulate pool creation for a given network.
 * Returns a summary suitable for inclusion in smoke test results.
 *
 * @param networkName - The network name (e.g., 'base', 'plume')
 * @param lendingPoolManagerAddress - Address of LendingPoolManager contract
 * @param poolAdminMultisig - Address with LENDING_POOL_CREATOR role
 * @param verbose - Whether to print detailed output (default: false)
 * @returns Summary of simulation result
 */
export async function simulateCreatePool(
    networkName: string,
    lendingPoolManagerAddress: string,
    poolAdminMultisig: string,
    verbose: boolean = false,
): Promise<TenderlySimulationSummary> {
    // Check if Tenderly credentials are configured
    const TENDERLY_ACCESS_KEY = process.env.TENDERLY_ACCESS_KEY;
    const TENDERLY_ACCOUNT_ID = process.env.TENDERLY_ACCOUNT_ID;
    const TENDERLY_PROJECT_SLUG = process.env.TENDERLY_PROJECT_SLUG;

    if (!TENDERLY_ACCESS_KEY || !TENDERLY_ACCOUNT_ID || !TENDERLY_PROJECT_SLUG) {
        return {
            success: false,
            skipped: true,
            skipReason: 'Tenderly credentials not configured (TENDERLY_ACCESS_KEY, TENDERLY_ACCOUNT_ID, TENDERLY_PROJECT_SLUG)',
        };
    }

    try {
        const networkId = getNetworkId(networkName);

        // Prepare pool creation transaction
        const poolConfig = getDefaultPoolConfig(poolAdminMultisig);

        // Encode the createPool call
        const lendingPoolManager = LendingPoolManager__factory.createInterface();
        const calldata = lendingPoolManager.encodeFunctionData('createPool', [poolConfig]);

        if (verbose) {
            console.log(`\n📡 Simulating createPool transaction on Tenderly...`);
            console.log(`   Network: ${networkName} (ID: ${networkId})`);
            console.log(`   From: ${poolAdminMultisig}`);
            console.log(`   To: ${lendingPoolManagerAddress}`);
        }

        // Simulate transaction
        const result = await simulateTransaction(
            networkId,
            poolAdminMultisig,
            lendingPoolManagerAddress,
            calldata
        );

        const dashboardUrl = `https://dashboard.tenderly.co/${TENDERLY_ACCOUNT_ID}/${TENDERLY_PROJECT_SLUG}/simulator/${result.simulation.id}`;

        if (result.transaction.status) {
            return {
                success: true,
                simulationId: result.simulation.id,
                gasUsed: result.simulation.gasUsed,
                dashboardUrl,
            };
        } else {
            return {
                success: false,
                simulationId: result.simulation.id,
                errorMessage: result.transaction.error_message || 'Simulation failed without error message',
                dashboardUrl,
            };
        }
    } catch (error) {
        return {
            success: false,
            errorMessage: error instanceof Error ? error.message : String(error),
        };
    }
}

async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);
    const networkId = getNetworkId(networkName);

    console.log('\n========================================');
    console.log('Tenderly Pool Creation Simulation');
    console.log('========================================\n');

    console.log(`Network: ${chainConfig.name} (${networkName})`);
    console.log(`Chain ID: ${chainConfig.chainId}`);
    console.log(`Network ID for Tenderly: ${networkId}`);

    // Get deployment addresses
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);
    const addresses = addressFile.getContractAddresses();

    const lendingPoolManagerAddress = addresses.LendingPoolManager?.address;
    if (!lendingPoolManagerAddress) {
        throw new Error('LendingPoolManager not found in deployment file');
    }

    console.log(`\nLendingPoolManager: ${lendingPoolManagerAddress}`);

    // Get the pool admin multisig that should have LENDING_POOL_CREATOR role
    const poolAdminMultisig = chainConfig.poolAdminMultisig;
    if (!poolAdminMultisig) {
        throw new Error(
            `Pool admin multisig not configured for ${networkName}. ` +
                `Set it in scripts/_config/chains.ts or via POOL_ADMIN_MULTISIG env variable.`
        );
    }

    console.log(`Pool Admin Multisig (LENDING_POOL_CREATOR): ${poolAdminMultisig}`);

    // Show pool configuration details
    const poolConfig = getDefaultPoolConfig(poolAdminMultisig);
    console.log(`\nPool Configuration:`);
    console.log(`  Name: ${poolConfig.poolName}`);
    console.log(`  Symbol: ${poolConfig.poolSymbol}`);
    console.log(`  Tranches: ${poolConfig.tranches.length}`);
    console.log(
        `  Tranche 0: ${Number(poolConfig.tranches[0].ratio) / 100}% @ ${(Number(poolConfig.tranches[0].interestRate) / 1e16).toFixed(2)}% APY`
    );
    console.log(
        `  Tranche 1: ${Number(poolConfig.tranches[1].ratio) / 100}% @ ${(Number(poolConfig.tranches[1].interestRate) / 1e16).toFixed(2)}% APY`
    );
    console.log();

    // Run simulation
    const summary = await simulateCreatePool(
        networkName,
        lendingPoolManagerAddress,
        poolAdminMultisig,
        true // verbose
    );

    console.log('========================================');
    console.log('Simulation Result');
    console.log('========================================\n');

    if (summary.skipped) {
        console.log(`⚠️  Simulation SKIPPED`);
        console.log(`\nReason: ${summary.skipReason}`);
        console.log('\nTo enable Tenderly simulations, set these environment variables:');
        console.log('  TENDERLY_ACCESS_KEY');
        console.log('  TENDERLY_ACCOUNT_ID');
        console.log('  TENDERLY_PROJECT_SLUG');
        console.log('\nSee scripts/tenderly/README.md for setup instructions.');
    } else if (summary.success) {
        console.log(`✅ Simulation SUCCEEDED`);
        console.log(`\nSimulation ID: ${summary.simulationId}`);
        console.log(`Gas Used: ${summary.gasUsed}`);

        if (summary.dashboardUrl) {
            console.log(`\n🔗 View in Tenderly Dashboard:`);
            console.log(`   ${summary.dashboardUrl}`);
        }

        console.log(`\n✅ Pool creation with LENDING_POOL_CREATOR role works on ${chainConfig.name}!`);
    } else {
        console.log(`❌ Simulation FAILED`);
        if (summary.errorMessage) {
            console.log(`\nError: ${summary.errorMessage}`);
        }

        if (summary.dashboardUrl) {
            console.log(`\n🔗 View in Tenderly Dashboard:`);
            console.log(`   ${summary.dashboardUrl}`);
        }

        console.log(`\nThis likely means:`);
        console.log(
            `  1. The pool admin multisig (${poolAdminMultisig}) doesn't have LENDING_POOL_CREATOR role`
        );
        console.log(`  2. There's an issue with the pool configuration`);
        console.log(`  3. The contract has a revert condition that was hit`);
        process.exitCode = 1;
    }

    console.log('\n========================================\n');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
