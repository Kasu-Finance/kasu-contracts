/**
 * Verify UpgradeableBeacon and BeaconProxy contracts on block explorers via Etherscan V2 API.
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/admin/verifyBeacons.ts
 *   npx hardhat --network plume run scripts/admin/verifyBeacons.ts
 *
 *   # Also verify factory-created BeaconProxy instances (pools):
 *   BEACON_PROXY_ADDRESSES=0xAddr1,0xAddr2 npx hardhat --network xdc run scripts/admin/verifyBeacons.ts
 *
 * The script reads beacon addresses from .openzeppelin/{network}-addresses.json
 * and verifies them using the Standard JSON Input from @openzeppelin/upgrades-core.
 */

import * as fs from 'fs';
import * as path from 'path';
import hre from 'hardhat';

// Chain configurations for Etherscan V2 API
const CHAIN_CONFIGS: Record<number, { apiUrl: string; name: string }> = {
    50: { apiUrl: 'https://api.etherscan.io/v2/api?chainid=50', name: 'XDC' },
    98866: { apiUrl: 'https://explorer.plume.org/api/v2', name: 'Plume' },
    8453: { apiUrl: 'https://api.etherscan.io/v2/api?chainid=8453', name: 'Base' },
};

interface BeaconInfo {
    name: string;
    beacon: string;
    implementation: string;
}

// ABI-encode constructor args for UpgradeableBeacon(address implementation, address initialOwner)
function encodeBeaconConstructorArgs(implementation: string, initialOwner: string): string {
    const impl = implementation.toLowerCase().replace('0x', '').padStart(64, '0');
    const owner = initialOwner.toLowerCase().replace('0x', '').padStart(64, '0');
    return impl + owner;
}

// ABI-encode constructor args for BeaconProxy(address beacon, bytes data)
// For pool creation, data is the initialize calldata — but if we don't know it,
// we can try empty data (0x) which is common for uninitialized proxies.
function encodeBeaconProxyConstructorArgs(beacon: string, initData: string = ''): string {
    const beaconPadded = beacon.toLowerCase().replace('0x', '').padStart(64, '0');
    // bytes is dynamic, so: offset(32) + length(32) + data(padded to 32)
    const dataOffset = '0000000000000000000000000000000000000000000000000000000000000040';
    const cleanData = initData.replace('0x', '');
    const dataLength = (cleanData.length / 2).toString(16).padStart(64, '0');
    const dataPadded = cleanData ? cleanData.padEnd(Math.ceil(cleanData.length / 64) * 64, '0') : '';
    return beaconPadded + dataOffset + dataLength + dataPadded;
}

async function getBeaconsFromDeployment(network: string): Promise<{ beacons: BeaconInfo[]; deployer: string }> {
    const chainId = hre.network.config.chainId;
    const possiblePaths = [
        path.join(process.cwd(), '.openzeppelin', `${network}-addresses.json`),
        path.join(process.cwd(), '.openzeppelin', `unknown-${chainId}.json`),
    ];

    let addressesPath: string | null = null;
    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            addressesPath = p;
            break;
        }
    }

    if (!addressesPath) {
        throw new Error(`No deployment file found for network ${network}. Tried: ${possiblePaths.join(', ')}`);
    }

    const addresses = JSON.parse(fs.readFileSync(addressesPath, 'utf-8'));
    const beacons: BeaconInfo[] = [];

    // BeaconProxy entries in the deployment file
    const beaconContracts = ['LendingPool', 'PendingPool', 'LendingPoolTranche'];

    for (const name of beaconContracts) {
        const entry = addresses[name];
        if (entry && entry.proxyType === 'BeaconProxy' && entry.address && entry.implementation) {
            beacons.push({
                name,
                beacon: entry.address,
                implementation: entry.implementation,
            });
        }
    }

    // Try deployment file, then env variable, then fetch from on-chain beacon owner
    let deployer = addresses.deployer || addresses.Deployer || process.env.DEPLOYER_ADDRESS;
    if (!deployer && beacons.length > 0) {
        // Fetch the owner of the first beacon (UpgradeableBeacon.owner())
        const beacon = new hre.ethers.Contract(
            beacons[0].beacon,
            ['function owner() view returns (address)'],
            hre.ethers.provider,
        );
        deployer = await beacon.owner();
        console.log(`  Fetched beacon owner from chain: ${deployer}`);
    }
    if (!deployer) {
        throw new Error('Deployer address not found. Set DEPLOYER_ADDRESS env variable.');
    }

    return { beacons, deployer };
}

async function checkVerificationStatus(apiUrl: string, apiKey: string, guid: string): Promise<{ status: string; result: string }> {
    const params = new URLSearchParams({
        module: 'contract',
        action: 'checkverifystatus',
        guid: guid,
        apikey: apiKey,
    });

    const response = await fetch(`${apiUrl}&${params.toString()}`);
    const data = await response.json();
    return { status: data.status, result: data.result };
}

async function isAlreadyVerified(apiUrl: string, apiKey: string, address: string): Promise<boolean> {
    const params = new URLSearchParams({
        module: 'contract',
        action: 'getsourcecode',
        address: address,
        apikey: apiKey,
    });

    try {
        const response = await fetch(`${apiUrl}&${params.toString()}`);
        const data = await response.json() as any;
        if (data.status === '1' && Array.isArray(data.result) && data.result[0]) {
            return !!data.result[0].ContractName;
        }
    } catch {}
    return false;
}

async function verifyContract(
    apiUrl: string,
    apiKey: string,
    chainId: number,
    address: string,
    contractName: string,
    constructorArgs: string,
    standardJsonInput: object,
    compilerVersion: string,
): Promise<string> {
    const params = new URLSearchParams({
        module: 'contract',
        action: 'verifysourcecode',
        apikey: apiKey,
    });

    const formData = new URLSearchParams();
    formData.append('chainId', chainId.toString());
    formData.append('codeformat', 'solidity-standard-json-input');
    formData.append('sourceCode', JSON.stringify(standardJsonInput));
    formData.append('contractaddress', address);
    formData.append('contractname', contractName);
    formData.append('compilerversion', compilerVersion);
    formData.append('constructorArguements', constructorArgs);

    const response = await fetch(`${apiUrl}&${params.toString()}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString(),
    });

    const data = await response.json() as any;

    if (data.status === '1') {
        return data.result;
    } else {
        throw new Error(data.result || 'Verification submission failed');
    }
}

async function waitForVerification(apiUrl: string, apiKey: string, guid: string, maxAttempts = 10): Promise<boolean> {
    for (let i = 0; i < maxAttempts; i++) {
        await new Promise(resolve => setTimeout(resolve, 5000));

        const { result } = await checkVerificationStatus(apiUrl, apiKey, guid);

        if (result === 'Pass - Verified' || result === 'Already Verified') {
            return true;
        } else if (result.includes('Fail') || result.includes('Error')) {
            console.error(`  Verification failed: ${result}`);
            return false;
        }

        console.log(`  Checking status (${i + 1}/${maxAttempts}): ${result}`);
    }

    console.error('  Verification timed out');
    return false;
}

async function main() {
    const network = hre.network.name;
    const chainId = hre.network.config.chainId;

    if (!chainId) {
        throw new Error('Chain ID not configured for network');
    }

    const chainConfig = CHAIN_CONFIGS[chainId];
    if (!chainConfig) {
        throw new Error(`Unsupported chain ID: ${chainId}. Add configuration to CHAIN_CONFIGS.`);
    }

    console.log(`Beacon & BeaconProxy Verification Script`);
    console.log(`=========================================`);
    console.log(`Network: ${network} (${chainConfig.name})`);
    console.log(`Chain ID: ${chainId}\n`);

    const apiKey = process.env.ETHERSCAN_API_KEY || '';
    if (!apiKey) {
        console.warn('Warning: ETHERSCAN_API_KEY not set. Some chains may require it.\n');
    }

    // Load Standard JSON Input from project's build artifacts (correct compiler version)
    // For beacons: use the upgrades-core build info (solc 0.8.29 - matches UpgradeableBeacon deployment)
    const upgradesCoreJsonPath = path.join(
        process.cwd(),
        'node_modules',
        '@openzeppelin',
        'upgrades-core',
        'artifacts',
        'build-info-v5.json',
    );

    if (!fs.existsSync(upgradesCoreJsonPath)) {
        throw new Error(`upgrades-core build info not found: ${upgradesCoreJsonPath}`);
    }

    const upgradesCoreBuildInfo = JSON.parse(fs.readFileSync(upgradesCoreJsonPath, 'utf-8'));
    const beaconStandardJsonInput = {
        language: 'Solidity',
        sources: upgradesCoreBuildInfo.input.sources,
        settings: upgradesCoreBuildInfo.input.settings,
    };
    const beaconCompilerVersion = `v${upgradesCoreBuildInfo.solcLongVersion}`;

    // For beacon proxies: use the project's build info (solc 0.8.23 - BeaconProxy compiled as part of factory)
    const beaconProxyDbgPath = path.join(
        process.cwd(),
        'artifacts',
        '@openzeppelin',
        'contracts',
        'proxy',
        'beacon',
        'BeaconProxy.sol',
        'BeaconProxy.dbg.json',
    );

    let beaconProxyStandardJsonInput: object = beaconStandardJsonInput;
    let beaconProxyCompilerVersion = beaconCompilerVersion;

    if (fs.existsSync(beaconProxyDbgPath)) {
        const dbg = JSON.parse(fs.readFileSync(beaconProxyDbgPath, 'utf-8'));
        const buildInfoPath = path.resolve(path.dirname(beaconProxyDbgPath), dbg.buildInfo);
        const projectBuildInfo = JSON.parse(fs.readFileSync(buildInfoPath, 'utf-8'));
        beaconProxyStandardJsonInput = {
            language: 'Solidity',
            sources: projectBuildInfo.input.sources,
            settings: projectBuildInfo.input.settings,
        };
        beaconProxyCompilerVersion = `v${projectBuildInfo.solcLongVersion}`;
        console.log(`Loaded project build info (${beaconProxyCompilerVersion}) for BeaconProxy`);
    }

    console.log(`Loaded upgrades-core build info (${beaconCompilerVersion}) for UpgradeableBeacon\n`);

    // Get beacons from deployment file
    const { beacons, deployer } = await getBeaconsFromDeployment(network);
    console.log(`Found ${beacons.length} beacon contracts to verify`);
    console.log(`Deployer (initialOwner): ${deployer}\n`);

    const results: { name: string; address: string; success: boolean; error?: string }[] = [];

    // 1. Verify UpgradeableBeacon contracts
    console.log('=== Verifying UpgradeableBeacon contracts ===\n');
    for (const { name, beacon, implementation } of beacons) {
        console.log(`Verifying ${name} beacon: ${beacon}`);
        console.log(`  Implementation: ${implementation}`);

        if (await isAlreadyVerified(chainConfig.apiUrl, apiKey, beacon)) {
            console.log(`  Already verified!\n`);
            results.push({ name: `${name} (Beacon)`, address: beacon, success: true });
            continue;
        }

        const constructorArgs = encodeBeaconConstructorArgs(implementation, deployer);

        try {
            const guid = await verifyContract(
                chainConfig.apiUrl,
                apiKey,
                chainId,
                beacon,
                '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol:UpgradeableBeacon',
                constructorArgs,
                beaconStandardJsonInput,
                beaconCompilerVersion,
            );
            console.log(`  Submitted, GUID: ${guid}`);

            const success = await waitForVerification(chainConfig.apiUrl, apiKey, guid);
            results.push({ name: `${name} (Beacon)`, address: beacon, success });

            if (success) {
                console.log(`  Verified successfully!\n`);
            } else {
                console.log(`  Verification failed\n`);
            }
        } catch (error: any) {
            const errorMsg = error.message || String(error);
            if (errorMsg.toLowerCase().includes('already verified')) {
                console.log(`  Already verified!\n`);
                results.push({ name: `${name} (Beacon)`, address: beacon, success: true });
            } else {
                console.error(`  Error: ${errorMsg}\n`);
                results.push({ name: `${name} (Beacon)`, address: beacon, success: false, error: errorMsg });
            }
        }

        await new Promise(resolve => setTimeout(resolve, 3000));
    }

    // 2. Verify BeaconProxy instances (factory-created pools)
    const beaconProxyAddresses = process.env.BEACON_PROXY_ADDRESSES?.split(',').map(a => a.trim()).filter(Boolean) || [];

    if (beaconProxyAddresses.length > 0) {
        console.log('\n=== Verifying BeaconProxy instances ===\n');
        console.log(`Found ${beaconProxyAddresses.length} BeaconProxy address(es) to verify\n`);

        for (const proxyAddress of beaconProxyAddresses) {
            console.log(`Verifying BeaconProxy: ${proxyAddress}`);

            if (await isAlreadyVerified(chainConfig.apiUrl, apiKey, proxyAddress)) {
                console.log(`  Already verified!\n`);
                results.push({ name: `BeaconProxy`, address: proxyAddress, success: true });
                continue;
            }

            // For BeaconProxy, we need to figure out which beacon it points to and the init data.
            // We'll read the beacon address from EIP-1967 beacon slot on-chain.
            const BEACON_SLOT = '0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50';
            const beaconSlotValue = await hre.ethers.provider.getStorage(proxyAddress, BEACON_SLOT);
            const beaconAddress = '0x' + beaconSlotValue.slice(26); // extract address from 32-byte slot

            console.log(`  Beacon: ${beaconAddress}`);

            // Get constructor args from creation tx
            // BeaconProxy constructor: (address beacon, bytes data)
            // We need the actual init data from the creation tx
            const params = new URLSearchParams({
                module: 'account',
                action: 'txlist',
                address: proxyAddress,
                startblock: '0',
                endblock: '999999999',
                page: '1',
                offset: '1',
                sort: 'asc',
                apikey: apiKey,
            });

            let creationInput = '';
            try {
                const response = await fetch(`${chainConfig.apiUrl}&${params.toString()}`);
                const data = await response.json() as any;
                if (data.status === '1' && data.result && data.result[0]) {
                    // The creation tx input contains: deploy bytecode + constructor args
                    // We need to extract constructor args from the end
                    creationInput = data.result[0].input || '';
                }
            } catch {}

            if (!creationInput) {
                // Fallback: try with internal txs (contract created by factory)
                const internalParams = new URLSearchParams({
                    module: 'account',
                    action: 'txlistinternal',
                    address: proxyAddress,
                    startblock: '0',
                    endblock: '999999999',
                    page: '1',
                    offset: '1',
                    sort: 'asc',
                    apikey: apiKey,
                });

                try {
                    const response = await fetch(`${chainConfig.apiUrl}&${internalParams.toString()}`);
                    const data = await response.json() as any;
                    if (data.status === '1' && data.result) {
                        // For factory-created contracts, the creation code is in internal tx
                        console.log(`  Factory-created contract (internal tx)`);
                    }
                } catch {}
            }

            // BeaconProxy constructor: (address beacon, bytes data)
            // Factory creates with empty data: new BeaconProxy(beacon, "")
            const constructorArgs = encodeBeaconProxyConstructorArgs(beaconAddress);
            console.log(`  Constructor args: BeaconProxy(${beaconAddress}, "")`);

            try {
                const guid = await verifyContract(
                    chainConfig.apiUrl,
                    apiKey,
                    chainId,
                    proxyAddress,
                    '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol:BeaconProxy',
                    constructorArgs,
                    beaconProxyStandardJsonInput,
                    beaconProxyCompilerVersion,
                );
                console.log(`  Submitted, GUID: ${guid}`);

                const success = await waitForVerification(chainConfig.apiUrl, apiKey, guid);
                results.push({ name: 'BeaconProxy', address: proxyAddress, success });

                if (success) {
                    console.log(`  Verified successfully!\n`);
                } else {
                    console.log(`  Verification failed\n`);
                }
            } catch (error: any) {
                const errorMsg = error.message || String(error);
                if (errorMsg.toLowerCase().includes('already verified')) {
                    console.log(`  Already verified!\n`);
                    results.push({ name: 'BeaconProxy', address: proxyAddress, success: true });
                } else {
                    console.error(`  Error: ${errorMsg}\n`);
                    results.push({ name: 'BeaconProxy', address: proxyAddress, success: false, error: errorMsg });
                }
            }

            await new Promise(resolve => setTimeout(resolve, 3000));
        }
    } else {
        console.log('\nNo BEACON_PROXY_ADDRESSES specified. To verify factory-created pools, run:');
        console.log('  BEACON_PROXY_ADDRESSES=0xAddr1,0xAddr2 npx hardhat --network xdc run scripts/admin/verifyBeacons.ts\n');
    }

    // Summary
    console.log('\n========== SUMMARY ==========');
    const successful = results.filter(r => r.success);
    const failed = results.filter(r => !r.success);

    console.log(`\nSuccessful: ${successful.length}/${results.length}`);
    successful.forEach(r => console.log(`  ${r.name}: ${r.address}`));

    if (failed.length > 0) {
        console.log(`\nFailed: ${failed.length}/${results.length}`);
        failed.forEach(r => console.log(`  ${r.name}: ${r.address} - ${r.error || 'Unknown error'}`));
    }
}

main().catch(console.error);
