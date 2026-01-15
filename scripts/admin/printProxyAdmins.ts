import hre, { upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

type ProxyAdminProbe = {
    isProxyAdmin: boolean;
    owner: string;
};

async function probeProxyAdmin(address: string): Promise<ProxyAdminProbe> {
    const code = await hre.ethers.provider.getCode(address);
    if (!code || code === '0x') {
        return { isProxyAdmin: false, owner: '' };
    }

    try {
        const adminContract = new hre.ethers.Contract(
            address,
            ['function owner() view returns (address)'],
            hre.ethers.provider,
        );
        const owner = (await adminContract.owner()) as string;
        return { isProxyAdmin: true, owner };
    } catch {
        return { isProxyAdmin: false, owner: '' };
    }
}

async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);
    const addresses = addressFile.getContractAddresses() as Record<
        string,
        AddressEntry
    >;

    const rows: Array<{
        name: string;
        proxyType: string;
        proxyAddress: string;
        adminAddress: string;
        isProxyAdmin: boolean;
        proxyAdminOwner: string;
    }> = [];

    for (const [name, entry] of Object.entries(addresses)) {
        if (!entry || !entry.address || !entry.proxyType) {
            continue;
        }

        if (entry.proxyType !== 'TransparentProxy') {
            continue;
        }

        const adminAddress = await upgrades.erc1967.getAdminAddress(
            entry.address,
        );
        const proxyAdminProbe = await probeProxyAdmin(adminAddress);

        rows.push({
            name,
            proxyType: entry.proxyType,
            proxyAddress: entry.address,
            adminAddress,
            isProxyAdmin: proxyAdminProbe.isProxyAdmin,
            proxyAdminOwner: proxyAdminProbe.owner,
        });
    }

    if (rows.length === 0) {
        console.log('No transparent proxies found in deployment file.');
        return;
    }

    console.table(rows);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
