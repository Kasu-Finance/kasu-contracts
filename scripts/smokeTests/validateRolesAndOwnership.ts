import hre, { upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getChainConfig } from '../_config/chains';
import { KasuController__factory } from '../../typechain-types';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

type ValidationResult = {
    passed: boolean;
    message: string;
};

type OwnerProbe = {
    isValid: boolean;
    owner: string;
};

const ROLE_KASU_ADMIN = '0x0000000000000000000000000000000000000000000000000000000000000000';
const ROLE_PROTOCOL_FEE_CLAIMER = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('ROLE_PROTOCOL_FEE_CLAIMER'));
const ROLE_LENDING_POOL_CREATOR = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('ROLE_LENDING_POOL_CREATOR'));
const ROLE_LENDING_POOL_FACTORY = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('ROLE_LENDING_POOL_FACTORY'));

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
    addresses: Record<string, AddressEntry>,
): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];
    const transparentProxies: string[] = [];
    const beacons: string[] = [];

    // Collect all proxies and beacons
    for (const [name, entry] of Object.entries(addresses)) {
        if (!entry || !entry.address || !entry.proxyType) {
            continue;
        }

        if (entry.proxyType === 'TransparentProxy') {
            const adminAddress = await upgrades.erc1967.getAdminAddress(entry.address);
            const ownerProbe = await probeOwner(adminAddress);

            if (!ownerProbe.isValid) {
                results.push({
                    passed: false,
                    message: `❌ ${name}: ProxyAdmin owner could not be read`,
                });
            } else if (kasuMultisig && ownerProbe.owner.toLowerCase() !== kasuMultisig.toLowerCase()) {
                results.push({
                    passed: false,
                    message: `❌ ${name}: ProxyAdmin owner is ${ownerProbe.owner}, expected ${kasuMultisig}`,
                });
            } else if (!kasuMultisig) {
                results.push({
                    passed: true,
                    message: `⚠️  ${name}: ProxyAdmin owner is ${ownerProbe.owner} (no multisig configured for validation)`,
                });
            } else {
                results.push({
                    passed: true,
                    message: `✅ ${name}: ProxyAdmin owner is correct (${kasuMultisig})`,
                });
            }
            transparentProxies.push(name);
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

                if (kasuMultisig && owner.toLowerCase() !== kasuMultisig.toLowerCase()) {
                    results.push({
                        passed: false,
                        message: `❌ ${name}: Beacon owner is ${owner}, expected ${kasuMultisig}`,
                    });
                } else if (!kasuMultisig) {
                    results.push({
                        passed: true,
                        message: `⚠️  ${name}: Beacon owner is ${owner} (no multisig configured for validation)`,
                    });
                } else {
                    results.push({
                        passed: true,
                        message: `✅ ${name}: Beacon owner is correct (${kasuMultisig})`,
                    });
                }
                beacons.push(name);
            } catch (e) {
                results.push({
                    passed: false,
                    message: `❌ ${name}: Failed to read Beacon owner`,
                });
            }
        }
    }

    return results;
}

async function validateRoles(
    kasuMultisig: string,
    kasuControllerAddress: string,
    addresses: Record<string, AddressEntry>,
): Promise<ValidationResult[]> {
    const results: ValidationResult[] = [];
    const kasuController = KasuController__factory.connect(
        kasuControllerAddress,
        hre.ethers.provider,
    );

    // Check ROLE_KASU_ADMIN
    const hasKasuAdmin = await kasuController.hasRole(ROLE_KASU_ADMIN, kasuMultisig);
    if (!hasKasuAdmin) {
        results.push({
            passed: false,
            message: `❌ ROLE_KASU_ADMIN: ${kasuMultisig} does not have ROLE_KASU_ADMIN`,
        });
    } else {
        results.push({
            passed: true,
            message: `✅ ROLE_KASU_ADMIN: ${kasuMultisig} has ROLE_KASU_ADMIN`,
        });
    }

    // Check if LendingPoolFactory has ROLE_LENDING_POOL_FACTORY
    const lendingPoolFactory = addresses.LendingPoolFactory?.address;
    if (lendingPoolFactory) {
        const hasFactoryRole = await kasuController.hasRole(ROLE_LENDING_POOL_FACTORY, lendingPoolFactory);
        results.push({
            passed: hasFactoryRole,
            message: hasFactoryRole
                ? `✅ ROLE_LENDING_POOL_FACTORY: LendingPoolFactory (${lendingPoolFactory}) has the role`
                : `❌ ROLE_LENDING_POOL_FACTORY: LendingPoolFactory does not have the role`,
        });
    } else {
        results.push({
            passed: false,
            message: `❌ ROLE_LENDING_POOL_FACTORY: LendingPoolFactory address not found`,
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
    console.log('Role & Ownership Validation');
    console.log('========================================\n');

    console.log(`Network: ${chainConfig.name} (${networkName})`);
    console.log(`Block: ${blockNumber}`);

    const kasuMultisig = chainConfig.kasuMultisig;
    if (kasuMultisig) {
        console.log(`Kasu Multisig: ${kasuMultisig}`);
    } else {
        console.log(`⚠️  Warning: No Kasu multisig configured for this network`);
    }
    console.log();

    const addresses = addressFile.getContractAddresses() as Record<string, AddressEntry>;

    // Get KasuController address
    const kasuControllerEntry = addresses.KasuController;
    if (!kasuControllerEntry || !kasuControllerEntry.address) {
        console.error('❌ KasuController not found in deployment file');
        process.exitCode = 1;
        return;
    }

    const allResults: ValidationResult[] = [];

    // Validate proxy ownership
    console.log('📋 Validating Proxy & Beacon Ownership...\n');
    const ownershipResults = await validateProxyOwnership(kasuMultisig, addresses);
    allResults.push(...ownershipResults);
    ownershipResults.forEach((r) => console.log(r.message));

    console.log('\n📋 Validating Roles on KasuController...\n');
    if (kasuMultisig) {
        const roleResults = await validateRoles(kasuMultisig, kasuControllerEntry.address, addresses);
        allResults.push(...roleResults);
        roleResults.forEach((r) => console.log(r.message));
    } else {
        console.log('⚠️  Skipping role validation (no multisig configured)');
    }

    // Summary
    const failedCount = allResults.filter((r) => !r.passed).length;
    const passedCount = allResults.filter((r) => r.passed).length;

    console.log('\n========================================');
    console.log('Summary');
    console.log('========================================');
    console.log(`Total checks: ${allResults.length}`);
    console.log(`✅ Passed: ${passedCount}`);
    console.log(`❌ Failed: ${failedCount}`);
    console.log('========================================\n');

    if (failedCount > 0) {
        console.error('❌ Smoke test FAILED');
        process.exitCode = 1;
    } else {
        console.log('✅ All smoke tests PASSED');
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
