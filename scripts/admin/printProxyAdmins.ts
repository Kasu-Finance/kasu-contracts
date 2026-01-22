import hre, { upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

type OwnerProbe = {
    isValid: boolean;
    owner: string;
};

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

async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);
    const addresses = addressFile.getContractAddresses() as Record<
        string,
        AddressEntry
    >;

    // Transparent Proxies
    const transparentRows: Array<{
        name: string;
        proxyAddress: string;
        proxyAdminAddress: string;
        proxyAdminOwner: string;
    }> = [];

    // Beacon Proxies
    const beaconRows: Array<{
        name: string;
        beaconAddress: string;
        implementationAddress: string;
        beaconOwner: string;
    }> = [];

    for (const [name, entry] of Object.entries(addresses)) {
        if (!entry || !entry.address || !entry.proxyType) {
            continue;
        }

        if (entry.proxyType === 'TransparentProxy') {
            const adminAddress = await upgrades.erc1967.getAdminAddress(
                entry.address,
            );
            const ownerProbe = await probeOwner(adminAddress);

            transparentRows.push({
                name,
                proxyAddress: entry.address,
                proxyAdminAddress: adminAddress,
                proxyAdminOwner: ownerProbe.isValid ? ownerProbe.owner : 'N/A',
            });
        } else if (
            entry.proxyType === 'UpgradeableBeacon' ||
            entry.proxyType === 'BeaconProxy'
        ) {
            // BeaconProxy in deployment file = the Beacon contract address
            // Get its implementation and owner
            try {
                const beacon = new hre.ethers.Contract(
                    entry.address,
                    [
                        'function implementation() view returns (address)',
                        'function owner() view returns (address)',
                    ],
                    hre.ethers.provider,
                );
                const [implementation, owner] = await Promise.all([
                    beacon.implementation() as Promise<string>,
                    beacon.owner() as Promise<string>,
                ]);

                beaconRows.push({
                    name,
                    beaconAddress: entry.address,
                    implementationAddress: implementation,
                    beaconOwner: owner,
                });
            } catch (e) {
                beaconRows.push({
                    name,
                    beaconAddress: entry.address,
                    implementationAddress: 'Error reading',
                    beaconOwner: 'Error reading',
                });
            }
        }
    }

    if (transparentRows.length === 0 && beaconRows.length === 0) {
        console.log('No proxies or beacons found in deployment file.');
        return;
    }

    if (transparentRows.length > 0) {
        console.log('\n=== Transparent Proxies (ProxyAdmin pattern) ===');
        console.log(
            'Each proxy has its own ProxyAdmin. Upgrade affects only that proxy.\n',
        );
        console.table(transparentRows);
    }

    if (beaconRows.length > 0) {
        console.log('\n=== Upgradeable Beacons ===');
        console.log(
            'Multiple BeaconProxies share a Beacon. Upgrading the Beacon upgrades all proxies.\n',
        );
        console.table(beaconRows);
    }

    // Summary of unique owners
    const allOwners = new Set<string>();
    transparentRows.forEach((r) => {
        if (r.proxyAdminOwner && r.proxyAdminOwner !== 'N/A')
            allOwners.add(r.proxyAdminOwner);
    });
    beaconRows.forEach((r) => {
        if (r.beaconOwner && r.beaconOwner !== 'Error reading')
            allOwners.add(r.beaconOwner);
    });

    console.log('\n=== Unique Owners ===');
    allOwners.forEach((owner) => console.log(`  ${owner}`));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
