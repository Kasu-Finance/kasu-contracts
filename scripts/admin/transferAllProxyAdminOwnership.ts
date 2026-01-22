import hre, { upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getAccounts } from '../_modules/getAccounts';

type AddressEntry = {
    address?: string;
    proxyType?: string;
};

type ProxyAdminInfo = {
    proxyName: string;
    proxyAddress: string;
    adminAddress: string;
    currentOwner: string;
};

async function getProxyAdminOwner(adminAddress: string): Promise<string> {
    const code = await hre.ethers.provider.getCode(adminAddress);
    if (!code || code === '0x') {
        return '';
    }

    try {
        const adminContract = new hre.ethers.Contract(
            adminAddress,
            ['function owner() view returns (address)'],
            hre.ethers.provider,
        );
        return (await adminContract.owner()) as string;
    } catch {
        return '';
    }
}

async function main() {
    const networkName = hre.network.name;
    const newOwner = process.env.NEW_PROXY_ADMIN_OWNER;

    if (!newOwner) {
        console.error(
            'Error: NEW_PROXY_ADMIN_OWNER environment variable is required',
        );
        console.log(
            'Usage: NEW_PROXY_ADMIN_OWNER=0x... npx hardhat --network <network> run scripts/admin/transferAllProxyAdminOwnership.ts',
        );
        process.exitCode = 1;
        return;
    }

    if (!hre.ethers.isAddress(newOwner)) {
        console.error(`Error: Invalid address format: ${newOwner}`);
        process.exitCode = 1;
        return;
    }

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);
    const addresses = addressFile.getContractAddresses() as Record<
        string,
        AddressEntry
    >;

    const signers = await getAccounts(networkName);
    const adminSigner = signers[1]; // Admin signer (index 1 per deploy.ts convention)
    const signerAddress = await adminSigner.getAddress();

    console.log(`Network: ${networkName}`);
    console.log(`Signer: ${signerAddress}`);
    console.log(`New owner: ${newOwner}`);
    console.log();

    // Collect all ProxyAdmin info
    const proxyAdmins: ProxyAdminInfo[] = [];
    const uniqueAdmins = new Map<string, ProxyAdminInfo[]>();

    for (const [name, entry] of Object.entries(addresses)) {
        if (!entry || !entry.address || entry.proxyType !== 'TransparentProxy') {
            continue;
        }

        const adminAddress = await upgrades.erc1967.getAdminAddress(
            entry.address,
        );
        const currentOwner = await getProxyAdminOwner(adminAddress);

        const info: ProxyAdminInfo = {
            proxyName: name,
            proxyAddress: entry.address,
            adminAddress,
            currentOwner,
        };

        proxyAdmins.push(info);

        // Group by admin address
        if (!uniqueAdmins.has(adminAddress)) {
            uniqueAdmins.set(adminAddress, []);
        }
        uniqueAdmins.get(adminAddress)!.push(info);
    }

    if (proxyAdmins.length === 0) {
        console.log('No transparent proxies found in deployment file.');
        return;
    }

    console.log(`Found ${proxyAdmins.length} transparent proxies`);
    console.log(`Found ${uniqueAdmins.size} unique ProxyAdmin contracts`);
    console.log();

    // Filter to only ProxyAdmins owned by the signer
    const adminsToTransfer: string[] = [];
    const adminsAlreadyOwned: string[] = [];
    const adminsNotOwned: string[] = [];

    for (const [adminAddress, proxies] of uniqueAdmins) {
        const currentOwner = proxies[0].currentOwner;

        if (currentOwner.toLowerCase() === newOwner.toLowerCase()) {
            adminsAlreadyOwned.push(adminAddress);
            console.log(
                `ProxyAdmin ${adminAddress} already owned by ${newOwner}`,
            );
            console.log(`  Manages: ${proxies.map((p) => p.proxyName).join(', ')}`);
        } else if (currentOwner.toLowerCase() === signerAddress.toLowerCase()) {
            adminsToTransfer.push(adminAddress);
            console.log(`ProxyAdmin ${adminAddress} will be transferred`);
            console.log(`  Current owner: ${currentOwner}`);
            console.log(`  Manages: ${proxies.map((p) => p.proxyName).join(', ')}`);
        } else {
            adminsNotOwned.push(adminAddress);
            console.log(
                `ProxyAdmin ${adminAddress} NOT owned by signer - skipping`,
            );
            console.log(`  Current owner: ${currentOwner}`);
            console.log(`  Manages: ${proxies.map((p) => p.proxyName).join(', ')}`);
        }
        console.log();
    }

    if (adminsToTransfer.length === 0) {
        console.log('No ProxyAdmins to transfer.');
        if (adminsAlreadyOwned.length > 0) {
            console.log(
                `${adminsAlreadyOwned.length} ProxyAdmin(s) already owned by target.`,
            );
        }
        if (adminsNotOwned.length > 0) {
            console.log(
                `${adminsNotOwned.length} ProxyAdmin(s) not owned by signer - cannot transfer.`,
            );
        }
        return;
    }

    console.log('---');
    console.log(
        `Transferring ownership of ${adminsToTransfer.length} ProxyAdmin(s) to ${newOwner}...`,
    );
    console.log();

    const proxyAdminAbi = [
        'function owner() view returns (address)',
        'function transferOwnership(address newOwner)',
    ];

    for (const adminAddress of adminsToTransfer) {
        const proxyAdmin = new hre.ethers.Contract(
            adminAddress,
            proxyAdminAbi,
            adminSigner,
        );

        console.log(`Transferring ProxyAdmin ${adminAddress}...`);
        const tx = await proxyAdmin.transferOwnership(newOwner);
        console.log(`  TX: ${tx.hash}`);
        await tx.wait(1);

        // Verify
        const newOwnerVerified = await proxyAdmin.owner();
        if (newOwnerVerified.toLowerCase() === newOwner.toLowerCase()) {
            console.log(`  Success: New owner is ${newOwnerVerified}`);
        } else {
            console.error(
                `  Warning: Owner is ${newOwnerVerified}, expected ${newOwner}`,
            );
        }
        console.log();
    }

    console.log('---');
    console.log('Summary:');
    console.log(`  Transferred: ${adminsToTransfer.length}`);
    console.log(`  Already owned by target: ${adminsAlreadyOwned.length}`);
    console.log(`  Not owned by signer (skipped): ${adminsNotOwned.length}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
