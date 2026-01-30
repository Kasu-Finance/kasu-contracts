import hre, { upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getChainConfig } from '../_config/chains';
import { getAccounts } from '../_modules/getAccounts';
import {
    KasuController__factory,
    LendingPoolManager__factory,
    SystemVariables__factory,
} from '../../typechain-types';
import { validatePoolSpecificRoles, PoolValidationResult } from './_modules/poolRoleValidation';
import { discoverPoolAddresses } from './_modules/poolDiscovery';
import { simulateCreatePool } from '../tenderly/simulateCreatePool';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

type ValidationResult = {
    category: string;
    passed: boolean;
    message: string;
};

type OwnerProbe = {
    isValid: boolean;
    owner: string;
};

// Global role constants
const ROLE_KASU_ADMIN = '0x0000000000000000000000000000000000000000000000000000000000000000';
const ROLE_PROTOCOL_FEE_CLAIMER = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_PROTOCOL_FEE_CLAIMER'),
);
const ROLE_LENDING_POOL_CREATOR = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_LENDING_POOL_CREATOR'),
);
const ROLE_LENDING_POOL_FACTORY = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_LENDING_POOL_FACTORY'),
);

// Note: Pool-specific roles (ROLE_POOL_ADMIN, ROLE_POOL_MANAGER, etc.)
// are validated per-pool in validatePoolRoles.ts, not here

async function probeOwner(address: string): Promise<OwnerProbe> {
    const code = await hre.ethers.provider.getCode(address);
    if (!code || code === '0x') {
        return { isValid: false, owner: '' };
    }

    try {
        const contract = new hre.ethers.Contract(
            address,
            ['function owner() view returns (address)'],
            hre.ethers.provider,
        );
        const owner = (await contract.owner()) as string;
        return { isValid: true, owner };
    } catch {
        return { isValid: false, owner: '' };
    }
}

async function validateProxyOwnership(
    kasuMultisig: string,
    deployerAddress: string,
    addresses: Record<string, AddressEntry>,
): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];

    for (const [name, entry] of Object.entries(addresses)) {
        if (!entry || !entry.address || !entry.proxyType) {
            continue;
        }

        if (entry.proxyType === 'TransparentProxy') {
            const adminAddress = await upgrades.erc1967.getAdminAddress(entry.address);
            const ownerProbe = await probeOwner(adminAddress);

            if (!ownerProbe.isValid) {
                results.push({
                    category: 'Proxy Ownership',
                    passed: false,
                    message: `${name}: ProxyAdmin owner could not be read`,
                });
            } else if (deployerAddress && ownerProbe.owner.toLowerCase() === deployerAddress.toLowerCase()) {
                results.push({
                    category: 'Proxy Ownership',
                    passed: false,
                    message: `${name}: ProxyAdmin owned by deployer (${ownerProbe.owner})`,
                });
            } else if (kasuMultisig && ownerProbe.owner.toLowerCase() !== kasuMultisig.toLowerCase()) {
                results.push({
                    category: 'Proxy Ownership',
                    passed: false,
                    message: `${name}: ProxyAdmin owned by ${ownerProbe.owner}, expected Kasu multisig (${kasuMultisig})`,
                });
            } else if (!kasuMultisig) {
                results.push({
                    category: 'Proxy Ownership',
                    passed: true,
                    message: `${name}: ProxyAdmin owned by ${ownerProbe.owner} (no Kasu multisig configured)`,
                });
            } else {
                results.push({
                    category: 'Proxy Ownership',
                    passed: true,
                    message: `${name}: ProxyAdmin owned by Kasu multisig (${kasuMultisig})`,
                });
            }
        } else if (
            entry.proxyType === 'UpgradeableBeacon' ||
            entry.proxyType === 'BeaconProxy'
        ) {
            try {
                const beacon = new hre.ethers.Contract(
                    entry.address,
                    ['function owner() view returns (address)'],
                    hre.ethers.provider,
                );
                const owner = (await beacon.owner()) as string;

                if (deployerAddress && owner.toLowerCase() === deployerAddress.toLowerCase()) {
                    results.push({
                        category: 'Beacon Ownership',
                        passed: false,
                        message: `${name}: Beacon owned by deployer (${owner})`,
                    });
                } else if (kasuMultisig && owner.toLowerCase() !== kasuMultisig.toLowerCase()) {
                    results.push({
                        category: 'Beacon Ownership',
                        passed: false,
                        message: `${name}: Beacon owned by ${owner}, expected Kasu multisig (${kasuMultisig})`,
                    });
                } else if (!kasuMultisig) {
                    results.push({
                        category: 'Beacon Ownership',
                        passed: true,
                        message: `${name}: Beacon owned by ${owner} (no Kasu multisig configured)`,
                    });
                } else {
                    results.push({
                        category: 'Beacon Ownership',
                        passed: true,
                        message: `${name}: Beacon owned by Kasu multisig (${kasuMultisig})`,
                    });
                }
            } catch (e) {
                results.push({
                    category: 'Beacon Ownership',
                    passed: false,
                    message: `${name}: Failed to read Beacon owner`,
                });
            }
        }
    }

    return results;
}

async function validateKasuControllerRoles(
    kasuMultisig: string,
    poolManagerMultisig: string,
    poolAdminMultisig: string,
    protocolFeeClaimer: string,
    deployerAddress: string,
    kasuControllerAddress: string,
    addresses: Record<string, AddressEntry>,
): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];
    const kasuController = KasuController__factory.connect(
        kasuControllerAddress,
        hre.ethers.provider,
    );

    // Check ROLE_KASU_ADMIN on multisig
    if (kasuMultisig) {
        const hasKasuAdmin = await kasuController.hasRole(ROLE_KASU_ADMIN, kasuMultisig);
        results.push({
            category: 'Roles',
            passed: hasKasuAdmin,
            message: hasKasuAdmin
                ? `ROLE_KASU_ADMIN: Kasu multisig has the role`
                : `ROLE_KASU_ADMIN: Kasu multisig does NOT have the role`,
        });
    }

    // Check deployer does NOT have ROLE_KASU_ADMIN (if deployer address is available)
    if (deployerAddress) {
        const deployerHasAdmin = await kasuController.hasRole(ROLE_KASU_ADMIN, deployerAddress);
        results.push({
            category: 'Roles',
            passed: !deployerHasAdmin,
            message: deployerHasAdmin
                ? `ROLE_KASU_ADMIN: Deployer still has admin role (should be revoked)`
                : `ROLE_KASU_ADMIN: Deployer correctly does NOT have admin role`,
        });
    }

    // Check ROLE_LENDING_POOL_FACTORY is set on LendingPoolFactory
    const lendingPoolFactory = addresses.LendingPoolFactory?.address;
    if (lendingPoolFactory) {
        const hasFactoryRole = await kasuController.hasRole(ROLE_LENDING_POOL_FACTORY, lendingPoolFactory);
        results.push({
            category: 'Roles',
            passed: hasFactoryRole,
            message: hasFactoryRole
                ? `ROLE_LENDING_POOL_FACTORY: LendingPoolFactory has the role`
                : `ROLE_LENDING_POOL_FACTORY: LendingPoolFactory does NOT have the role`,
        });
    } else {
        results.push({
            category: 'Roles',
            passed: false,
            message: `ROLE_LENDING_POOL_FACTORY: LendingPoolFactory address not found`,
        });
    }

    // Check ROLE_LENDING_POOL_CREATOR (global role)
    if (poolAdminMultisig) {
        const hasCreatorRole = await kasuController.hasRole(ROLE_LENDING_POOL_CREATOR, poolAdminMultisig);
        results.push({
            category: 'Roles',
            passed: hasCreatorRole,
            message: hasCreatorRole
                ? `ROLE_LENDING_POOL_CREATOR: Granted to pool admin multisig (${poolAdminMultisig})`
                : `ROLE_LENDING_POOL_CREATOR: NOT granted to pool admin multisig (${poolAdminMultisig})`,
        });
    } else {
        results.push({
            category: 'Roles',
            passed: true,
            message: `ROLE_LENDING_POOL_CREATOR: Pool admin multisig not configured (skipping)`,
        });
    }

    // Note: ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER, ROLE_POOL_MANAGER, ROLE_POOL_FUNDS_MANAGER
    // are POOL-SPECIFIC roles (validated per pool in the Pool-Specific Roles section below)

    // Check ROLE_PROTOCOL_FEE_CLAIMER - compare to expected address
    if (protocolFeeClaimer) {
        const hasRole = await kasuController.hasRole(ROLE_PROTOCOL_FEE_CLAIMER, protocolFeeClaimer);

        if (hasRole) {
            // Check if expected address is the deployer (which would be incorrect)
            const isDeployer = deployerAddress && protocolFeeClaimer.toLowerCase() === deployerAddress.toLowerCase();
            results.push({
                category: 'Roles',
                passed: !isDeployer,
                message: isDeployer
                    ? `ROLE_PROTOCOL_FEE_CLAIMER: Granted to expected address (${protocolFeeClaimer}) - but this is the deployer, should be changed`
                    : `ROLE_PROTOCOL_FEE_CLAIMER: Correctly granted to expected address (${protocolFeeClaimer})`,
            });
        } else {
            // Expected address doesn't have the role - check who does
            const potentialClaimers: Array<{ address: string; label: string }> = [];
            if (kasuMultisig) potentialClaimers.push({ address: kasuMultisig, label: 'Kasu multisig' });
            if (poolAdminMultisig) potentialClaimers.push({ address: poolAdminMultisig, label: 'pool admin multisig' });
            if (poolManagerMultisig) potentialClaimers.push({ address: poolManagerMultisig, label: 'pool manager multisig' });
            if (deployerAddress) potentialClaimers.push({ address: deployerAddress, label: 'deployer' });

            let actualClaimerFound = false;
            let actualClaimerAddress = '';
            let actualClaimerLabel = '';

            for (const { address, label } of potentialClaimers) {
                if (await kasuController.hasRole(ROLE_PROTOCOL_FEE_CLAIMER, address)) {
                    actualClaimerFound = true;
                    actualClaimerAddress = address;
                    actualClaimerLabel = label;
                    break;
                }
            }

            if (actualClaimerFound) {
                results.push({
                    category: 'Roles',
                    passed: false,
                    message: `ROLE_PROTOCOL_FEE_CLAIMER: Granted to ${actualClaimerLabel} (${actualClaimerAddress}) but expected ${protocolFeeClaimer}`,
                });
            } else {
                results.push({
                    category: 'Roles',
                    passed: false,
                    message: `ROLE_PROTOCOL_FEE_CLAIMER: Not granted to expected address (${protocolFeeClaimer}) or any known address`,
                });
            }
        }
    } else {
        // No expected address configured - just report who has the role
        const potentialClaimers: Array<{ address: string; label: string }> = [];
        if (kasuMultisig) potentialClaimers.push({ address: kasuMultisig, label: 'Kasu multisig' });
        if (poolAdminMultisig) potentialClaimers.push({ address: poolAdminMultisig, label: 'pool admin multisig' });
        if (poolManagerMultisig) potentialClaimers.push({ address: poolManagerMultisig, label: 'pool manager multisig' });
        if (deployerAddress) potentialClaimers.push({ address: deployerAddress, label: 'deployer' });

        let feeClaimerFound = false;
        let feeClaimerLabel = '';
        let feeClaimerAddress = '';

        for (const { address, label } of potentialClaimers) {
            if (await kasuController.hasRole(ROLE_PROTOCOL_FEE_CLAIMER, address)) {
                feeClaimerFound = true;
                feeClaimerAddress = address;
                feeClaimerLabel = label;
                break;
            }
        }

        if (feeClaimerFound) {
            const isDeployer = deployerAddress && feeClaimerAddress.toLowerCase() === deployerAddress.toLowerCase();
            results.push({
                category: 'Roles',
                passed: !isDeployer,
                message: isDeployer
                    ? `ROLE_PROTOCOL_FEE_CLAIMER: Granted to ${feeClaimerLabel} (${feeClaimerAddress}) - should be changed (no expected address configured)`
                    : `ROLE_PROTOCOL_FEE_CLAIMER: Granted to ${feeClaimerLabel} (${feeClaimerAddress}) (no expected address configured)`,
            });
        } else {
            results.push({
                category: 'Roles',
                passed: false,
                message: `ROLE_PROTOCOL_FEE_CLAIMER: Not granted to any known address - needs to be set (no expected address configured)`,
            });
        }
    }

    return results;
}

async function validateProtocolFeeReceiver(
    deployerAddress: string,
    systemVariablesAddress: string,
): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];

    try {
        const systemVariables = SystemVariables__factory.connect(
            systemVariablesAddress,
            hre.ethers.provider,
        );

        const protocolFeeReceiver = await systemVariables.protocolFeeReceiver();

        if (protocolFeeReceiver === hre.ethers.ZeroAddress) {
            results.push({
                category: 'Protocol Config',
                passed: false,
                message: `protocolFeeReceiver: Not set (zero address) - needs to be configured`,
            });
        } else if (deployerAddress && protocolFeeReceiver.toLowerCase() === deployerAddress.toLowerCase()) {
            results.push({
                category: 'Protocol Config',
                passed: false,
                message: `protocolFeeReceiver: Set to deployer (${protocolFeeReceiver}) - should be changed`,
            });
        } else {
            results.push({
                category: 'Protocol Config',
                passed: true,
                message: `protocolFeeReceiver: ${protocolFeeReceiver}`,
            });
        }
    } catch (error) {
        results.push({
            category: 'Protocol Config',
            passed: false,
            message: `protocolFeeReceiver: Could not read - SystemVariables may not be deployed`,
        });
    }

    return results;
}

async function main() {
    const networkName = hre.network.name;
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);
    const chainConfig = getChainConfig(networkName);

    console.log('\n========================================');
    console.log('Kasu Deployment Smoke Test');
    console.log('Complete Validation');
    console.log('========================================\n');

    console.log(`Network: ${chainConfig.name} (${networkName})`);
    console.log(`Block: ${blockNumber}`);

    const kasuMultisig = chainConfig.kasuMultisig;
    const poolManagerMultisig = chainConfig.poolManagerMultisig;
    const poolAdminMultisig = chainConfig.poolAdminMultisig;

    if (kasuMultisig) {
        console.log(`Kasu Multisig: ${kasuMultisig}`);
    } else {
        console.log(`⚠️  Warning: No Kasu multisig configured for this network`);
    }

    if (poolManagerMultisig) {
        console.log(`Pool Manager Multisig: ${poolManagerMultisig}`);
    }

    if (poolAdminMultisig) {
        console.log(`Pool Admin Multisig: ${poolAdminMultisig}`);
    }

    // Get deployer address from environment or signers
    let deployerAddress = '';

    // First try to get from DEPLOYER_ADDRESS env var (read-only, no private key needed)
    if (process.env.DEPLOYER_ADDRESS) {
        deployerAddress = process.env.DEPLOYER_ADDRESS;
        console.log(`Deployer: ${deployerAddress} (from env)`);
    } else {
        // Otherwise try to derive from DEPLOYER_KEY
        try {
            const signers = await getAccounts(networkName);
            if (signers && signers.length > 0) {
                deployerAddress = await signers[0].getAddress();
                console.log(`Deployer: ${deployerAddress}`);
            } else {
                console.log(`⚠️  Warning: No deployer configured - will skip deployer-specific checks`);
                console.log(`   To enable these checks, set DEPLOYER_ADDRESS or DEPLOYER_KEY in scripts/_env/.${networkName}.env`);
            }
        } catch (error) {
            console.log(`⚠️  Warning: Could not get deployer address - will skip deployer-specific checks`);
            console.log(`   To enable these checks, set DEPLOYER_ADDRESS or DEPLOYER_KEY in scripts/_env/.${networkName}.env`);
        }
    }
    console.log();

    const addresses = addressFile.getContractAddresses() as Record<string, AddressEntry>;

    // Verify required contracts exist
    const requiredContracts = ['KasuController', 'SystemVariables'];
    for (const contractName of requiredContracts) {
        if (!addresses[contractName] || !addresses[contractName].address) {
            console.error(`❌ ${contractName} not found in deployment file`);
            process.exitCode = 1;
            return;
        }
    }

    const allResults: ValidationResult[] = [];

    // 1. Validate proxy ownership
    console.log('📋 Validating Proxy & Beacon Ownership...\n');
    const ownershipResults = await validateProxyOwnership(
        kasuMultisig,
        deployerAddress,
        addresses,
    );
    allResults.push(...ownershipResults);

    // 2. Validate KasuController roles
    console.log('📋 Validating Roles on KasuController...\n');
    const roleResults = await validateKasuControllerRoles(
        kasuMultisig,
        poolManagerMultisig,
        poolAdminMultisig,
        chainConfig.protocolFeeClaimer,
        deployerAddress,
        addresses.KasuController!.address!,
        addresses,
    );
    allResults.push(...roleResults);

    // 3. Validate protocol fee receiver
    console.log('📋 Validating Protocol Configuration...\n');
    const protocolResults = await validateProtocolFeeReceiver(
        deployerAddress,
        addresses.SystemVariables!.address!,
    );
    allResults.push(...protocolResults);

    // 4. Validate pool-specific roles
    const poolValidationResults: PoolValidationResult[] = [];
    let poolAddresses: string[] = [];

    // Get pool addresses from chain config
    poolAddresses = chainConfig.lendingPoolAddresses || [];

    if (poolAddresses.length > 0) {
        console.log(`\n📋 Using ${poolAddresses.length} pool address(es) from chain config\n`);
    } else {
        // Try auto-discovery if no pools configured
        console.log(`\n📋 No pool addresses configured in chains.ts, attempting auto-discovery...\n`);
        const lendingPoolFactory = addresses.LendingPoolFactory?.address;
        if (lendingPoolFactory) {
            try {
                poolAddresses = await discoverPoolAddresses(lendingPoolFactory);
                if (poolAddresses.length > 0) {
                    console.log(`  Found ${poolAddresses.length} lending pool(s)`);
                    console.log(`  💡 Tip: Add these to chains.ts lendingPoolAddresses for faster validation\n`);
                } else {
                    console.log(`  No lending pools found (this is normal if pools haven't been created yet)`);
                }
            } catch (error) {
                console.warn(`  ⚠️  Could not auto-discover pools: ${error}`);
                console.log(`\n  💡 Please add pool addresses to scripts/_config/chains.ts:`);
                console.log(`     lendingPoolAddresses: ['0xPool1', '0xPool2', '0xPool3']\n`);
            }
        } else {
            console.log(`  ⚠️  LendingPoolFactory address not found - skipping pool discovery`);
        }
    }

    // Validate pool-specific roles if we have any pools
    if (poolAddresses.length > 0) {
        console.log(`\n📋 Validating Pool-Specific Roles for ${poolAddresses.length} pool(s)...\n`);

        for (const poolAddress of poolAddresses) {
            console.log(`  Pool: ${poolAddress}`);
            const poolResults = await validatePoolSpecificRoles(
                poolAddress,
                poolManagerMultisig,
                poolAdminMultisig,
                addresses.KasuController!.address!,
            );
            poolValidationResults.push(...poolResults);
        }
        console.log();
    } else {
        console.log();
    }

    // 5. Tenderly simulation: Test pool creation with LENDING_POOL_CREATOR role
    console.log('📋 Tenderly Simulation: Pool Creation...\n');

    const lendingPoolManagerAddress = addresses.LendingPoolManager?.address;
    if (!chainConfig.tenderlySupported) {
        console.log(`  ⚠️  Tenderly simulation skipped - not supported on ${chainConfig.name}\n`);
    } else if (lendingPoolManagerAddress && poolAdminMultisig) {
        const simulationResult = await simulateCreatePool(
            networkName,
            lendingPoolManagerAddress,
            poolAdminMultisig,
            false // not verbose - smoke test mode
        );

        if (simulationResult.skipped) {
            console.log(`  ⚠️  Tenderly simulation skipped`);
            console.log(`      ${simulationResult.skipReason}`);
            console.log(`      💡 To enable, set TENDERLY_ACCESS_KEY, TENDERLY_ACCOUNT_ID, and TENDERLY_PROJECT_SLUG`);
            console.log(`      See scripts/tenderly/README.md for setup instructions.\n`);
        } else if (simulationResult.success) {
            allResults.push({
                category: 'Tenderly Simulation',
                passed: true,
                message: `Pool creation simulation succeeded (gas: ${simulationResult.gasUsed})${simulationResult.dashboardUrl ? ` - ${simulationResult.dashboardUrl}` : ''}`,
            });
        } else {
            allResults.push({
                category: 'Tenderly Simulation',
                passed: false,
                message: `Pool creation simulation FAILED: ${simulationResult.errorMessage}${simulationResult.dashboardUrl ? ` - View: ${simulationResult.dashboardUrl}` : ''}`,
            });
        }
    } else {
        if (!lendingPoolManagerAddress) {
            console.log(`  ⚠️  LendingPoolManager address not found - skipping simulation\n`);
        } else if (!poolAdminMultisig) {
            console.log(`  ⚠️  Pool admin multisig not configured - skipping simulation\n`);
        }
    }

    // Display results by category
    const categories = [...new Set(allResults.map((r) => r.category))];
    for (const category of categories) {
        console.log(`\n--- ${category} ---`);
        const categoryResults = allResults.filter((r) => r.category === category);
        categoryResults.forEach((r) => {
            const icon = r.passed ? '✅' : '❌';
            console.log(`${icon} ${r.message}`);
        });
    }

    // Display pool-specific results
    if (poolValidationResults.length > 0) {
        console.log(`\n--- Pool-Specific Roles ---`);
        const uniquePoolAddresses = [...new Set(poolValidationResults.map((r) => r.poolAddress))];

        for (const poolAddr of uniquePoolAddresses) {
            console.log(`\n  Pool: ${poolAddr}`);
            const poolResults = poolValidationResults.filter((r) => r.poolAddress === poolAddr);
            poolResults.forEach((r) => {
                const icon = r.passed ? '✅' : '❌';
                console.log(`    ${icon} ${r.role}: ${r.message}`);
            });
        }
    } else if (poolAddresses.length === 0) {
        console.log(`\n--- Pool-Specific Roles ---`);
        console.log(`  No pools found - pool validation skipped`);
    }

    // Summary
    const globalFailedCount = allResults.filter((r) => !r.passed).length;
    const globalPassedCount = allResults.filter((r) => r.passed).length;
    const poolFailedCount = poolValidationResults.filter((r) => !r.passed).length;
    const poolPassedCount = poolValidationResults.filter((r) => r.passed).length;

    const totalChecks = allResults.length + poolValidationResults.length;
    const totalPassed = globalPassedCount + poolPassedCount;
    const totalFailed = globalFailedCount + poolFailedCount;

    console.log('\n========================================');
    console.log('Summary');
    console.log('========================================');
    console.log(`Global checks: ${allResults.length} (✅ ${globalPassedCount}, ❌ ${globalFailedCount})`);
    if (poolValidationResults.length > 0) {
        const poolCount = [...new Set(poolValidationResults.map((r) => r.poolAddress))].length;
        console.log(`Pool checks: ${poolValidationResults.length} across ${poolCount} pool(s) (✅ ${poolPassedCount}, ❌ ${poolFailedCount})`);
    }
    console.log(`---`);
    console.log(`Total checks: ${totalChecks}`);
    console.log(`✅ Passed: ${totalPassed}`);
    console.log(`❌ Failed: ${totalFailed}`);
    console.log('========================================\n');

    if (totalFailed > 0) {
        console.error('❌ Smoke test FAILED - Please review failed checks above');
        process.exitCode = 1;
    } else {
        console.log('✅ All smoke tests PASSED');
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
