/**
 * Verify TransparentUpgradeableProxy contracts on block explorers via Etherscan V2 API.
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/admin/verifyProxies.ts
 *   npx hardhat --network plume run scripts/admin/verifyProxies.ts
 *
 * The script reads proxy addresses from .openzeppelin/{network}-addresses.json
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

interface ProxyInfo {
    name: string;
    proxy: string;
    implementation: string;
}

// Generate ABI-encoded constructor arguments
// TransparentUpgradeableProxy(address _logic, address initialOwner, bytes _data)
function encodeConstructorArgs(implementation: string, initialOwner: string): string {
    const impl = implementation.toLowerCase().replace('0x', '').padStart(64, '0');
    const owner = initialOwner.toLowerCase().replace('0x', '').padStart(64, '0');
    const dataOffset = '0000000000000000000000000000000000000000000000000000000000000060';
    const dataLength = '0000000000000000000000000000000000000000000000000000000000000000';
    return impl + owner + dataOffset + dataLength;
}

async function getProxiesFromDeployment(network: string): Promise<{ proxies: ProxyInfo[]; deployer: string }> {
    // Try network-specific file first, then fall back to unknown-{chainId}
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
    const proxies: ProxyInfo[] = [];

    // Extract proxy contracts (those with both proxy and implementation)
    const proxyContracts = [
        'KasuController', 'KSULocking', 'KsuPrice', 'SystemVariables', 'FixedTermDeposit',
        'UserLoyaltyRewards', 'UserManager', 'Swapper', 'LendingPoolManager', 'FeeManager',
        'KasuAllowList', 'ClearingCoordinator', 'AcceptedRequestsCalculation', 'LendingPoolFactory',
        'KSULockBonus', 'KasuPoolExternalTVL',
        // Lite variants
        'KSULockingLite', 'KsuPriceLite', 'UserLoyaltyRewardsLite', 'UserManagerLite', 'ProtocolFeeManagerLite',
    ];

    for (const name of proxyContracts) {
        const proxyKey = `${name}Proxy`;
        const implKey = `${name}Impl`;

        if (addresses[proxyKey] && addresses[implKey]) {
            proxies.push({
                name,
                proxy: addresses[proxyKey],
                implementation: addresses[implKey],
            });
        }
    }

    // Get deployer address (initialOwner for proxies)
    const deployer = addresses.deployer || addresses.Deployer;
    if (!deployer) {
        throw new Error('Deployer address not found in deployment file');
    }

    return { proxies, deployer };
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

async function verifyContract(
    apiUrl: string,
    apiKey: string,
    chainId: number,
    proxyAddress: string,
    constructorArgs: string,
    standardJsonInput: object
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
    formData.append('contractaddress', proxyAddress);
    formData.append('contractname', '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy');
    formData.append('compilerversion', 'v0.8.29+commit.ab55807c');
    formData.append('constructorArguements', constructorArgs);

    const response = await fetch(`${apiUrl}&${params.toString()}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: formData.toString(),
    });

    const data = await response.json();

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

    console.log(`Proxy Contract Verification Script`);
    console.log(`===================================`);
    console.log(`Network: ${network} (${chainConfig.name})`);
    console.log(`Chain ID: ${chainId}\n`);

    const apiKey = process.env.ETHERSCAN_API_KEY || '';
    if (!apiKey) {
        console.warn('Warning: ETHERSCAN_API_KEY not set. Some chains may require it.\n');
    }

    // Load Standard JSON Input from upgrades-core
    const standardJsonPath = path.join(
        process.cwd(),
        'node_modules',
        '@openzeppelin',
        'upgrades-core',
        'artifacts',
        'build-info-v5.json'
    );

    if (!fs.existsSync(standardJsonPath)) {
        throw new Error(`Standard JSON input not found: ${standardJsonPath}`);
    }

    const buildInfo = JSON.parse(fs.readFileSync(standardJsonPath, 'utf-8'));
    const standardJsonInput = {
        language: 'Solidity',
        sources: buildInfo.input.sources,
        settings: buildInfo.input.settings,
    };

    console.log('Loaded Standard JSON Input from @openzeppelin/upgrades-core\n');

    // Get proxies from deployment file
    const { proxies, deployer } = await getProxiesFromDeployment(network);
    console.log(`Found ${proxies.length} proxy contracts to verify`);
    console.log(`Deployer (initialOwner): ${deployer}\n`);

    const results: { name: string; proxy: string; success: boolean; error?: string }[] = [];

    for (const { name, proxy, implementation } of proxies) {
        console.log(`Verifying ${name} proxy: ${proxy}`);
        console.log(`  Implementation: ${implementation}`);

        const constructorArgs = encodeConstructorArgs(implementation, deployer);

        try {
            const guid = await verifyContract(
                chainConfig.apiUrl,
                apiKey,
                chainId,
                proxy,
                constructorArgs,
                standardJsonInput
            );
            console.log(`  Submitted, GUID: ${guid}`);

            const success = await waitForVerification(chainConfig.apiUrl, apiKey, guid);
            results.push({ name, proxy, success });

            if (success) {
                console.log(`  ✓ Verified successfully!\n`);
            } else {
                console.log(`  ✗ Verification failed\n`);
            }
        } catch (error: any) {
            const errorMsg = error.message || String(error);
            if (errorMsg.toLowerCase().includes('already verified')) {
                console.log(`  ✓ Already verified!\n`);
                results.push({ name, proxy, success: true });
            } else {
                console.error(`  ✗ Error: ${errorMsg}\n`);
                results.push({ name, proxy, success: false, error: errorMsg });
            }
        }

        // Rate limiting
        await new Promise(resolve => setTimeout(resolve, 2000));
    }

    // Summary
    console.log('\n========== SUMMARY ==========');
    const successful = results.filter(r => r.success);
    const failed = results.filter(r => !r.success);

    console.log(`\nSuccessful: ${successful.length}/${results.length}`);
    successful.forEach(r => console.log(`  ✓ ${r.name}: ${r.proxy}`));

    if (failed.length > 0) {
        console.log(`\nFailed: ${failed.length}/${results.length}`);
        failed.forEach(r => console.log(`  ✗ ${r.name}: ${r.proxy} - ${r.error || 'Unknown error'}`));
    }
}

main().catch(console.error);
