import hre, { upgrades } from 'hardhat';
import * as dotenv from 'dotenv';
import * as path from 'path';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getChainConfig } from '../_config/chains';

type DeploymentMode = 'full' | 'lite';

type AddressEntry = {
    address?: string;
    implementation?: string;
    proxyType?: string;
    startBlock?: number;
};

type ValidationResult = {
    name: string;
    contractName: string;
    proxyAddress: string;
    implementationAddress: string;
    proxyType: string;
    bytecodeMatch: 'match' | 'mismatch' | 'unknown';
    etherscanVerified: boolean;
    upgradeable: boolean;
    verificationAttempted?: boolean;
    verificationSuccess?: boolean;
    error?: string;
};

// Map from export name to actual contract name based on deployment mode
function getContractName(exportName: string, mode: DeploymentMode): string {
    if (mode === 'lite') {
        const liteMap: Record<string, string> = {
            KSULocking: 'KSULockingLite',
            KsuPrice: 'KsuPriceLite',
            UserManager: 'UserManagerLite',
            UserLoyaltyRewards: 'UserLoyaltyRewardsLite',
            FeeManager: 'ProtocolFeeManagerLite',
        };
        return liteMap[exportName] || exportName;
    } else {
        // Full mode
        const fullMap: Record<string, string> = {
            KsuPrice: 'ManualKsuPrice',
        };
        return fullMap[exportName] || exportName;
    }
}

// Etherscan V2 API - single endpoint with chainId parameter
// https://docs.etherscan.io/v2-migration
const ETHERSCAN_V2_API = 'https://api.etherscan.io/v2/api';

// Chain ID mapping for Etherscan V2 API
const CHAIN_IDS: Record<string, number> = {
    mainnet: 1,
    sepolia: 11155111,
    base: 8453,
    'base-sepolia': 84532,
    baseSepolia: 84532,
    xdc: 50,
    'xdc-usdc': 50,
    'xdc-apothem': 51,
};

// Detect if the API URL is Blockscout
function isBlockscoutApi(apiUrl: string): boolean {
    return apiUrl.includes('/api/v2');
}

// Get block explorer API config
// Uses Etherscan V2 API for supported chains, falls back to custom chains for others
function getExplorerApiConfig(networkName: string): {
    apiUrl: string | null;
    apiKey: string;
    explorerName: string;
    chainId: number | null;
    isV2: boolean;
    isBlockscout: boolean;
} {
    const etherscanConfig = hre.config.etherscan;
    if (!etherscanConfig) {
        return { apiUrl: null, apiKey: '', explorerName: 'unknown', chainId: null, isV2: false, isBlockscout: false };
    }

    const apiKey = getApiKeyForNetwork(etherscanConfig.apiKey, networkName);

    // Check if this chain supports Etherscan V2 API
    const chainId = CHAIN_IDS[networkName];
    if (chainId) {
        return {
            apiUrl: ETHERSCAN_V2_API,
            apiKey,
            explorerName: `etherscan.io/v2 (chainId=${chainId})`,
            chainId,
            isV2: true,
            isBlockscout: false,
        };
    }

    // Fall back to custom chains (from hardhat.config.ts etherscan.customChains)
    const customChains = etherscanConfig.customChains || [];
    const customChain = customChains.find((c) => c.network === networkName);
    if (customChain) {
        const isBlockscout = isBlockscoutApi(customChain.urls.apiURL);
        return {
            apiUrl: customChain.urls.apiURL,
            apiKey,
            explorerName: new URL(customChain.urls.browserURL).hostname,
            chainId: null,
            isV2: false,
            isBlockscout,
        };
    }

    return { apiUrl: null, apiKey, explorerName: 'unknown', chainId: null, isV2: false, isBlockscout: false };
}

function getApiKeyForNetwork(
    apiKeyConfig: string | Record<string, string> | undefined,
    networkName: string,
): string {
    if (!apiKeyConfig) return '';
    if (typeof apiKeyConfig === 'string') return apiKeyConfig;

    // Handle network name variations (hardhat uses camelCase internally)
    const keyVariants = [
        networkName,
        networkName.replace(/-/g, ''), // base-sepolia -> basesepolia
        networkName.replace(/-([a-z])/g, (_, c) => c.toUpperCase()), // base-sepolia -> baseSepolia
    ];

    for (const variant of keyVariants) {
        if (apiKeyConfig[variant]) {
            return apiKeyConfig[variant];
        }
    }

    return '';
}

type ExplorerSourceResult = {
    verified: boolean;
    contractName: string;
    sourceCode: string | null; // The main contract source
    allSources: Record<string, string>; // All sources (for multi-file)
};

// Fetch source code from Blockscout API
async function fetchBlockscoutSource(
    address: string,
    baseApiUrl: string,
): Promise<ExplorerSourceResult> {
    const emptyResult: ExplorerSourceResult = {
        verified: false,
        contractName: '',
        sourceCode: null,
        allSources: {},
    };

    try {
        // First, check if contract is verified
        const addressUrl = `${baseApiUrl}/addresses/${address}`;
        const addressResponse = await fetch(addressUrl);
        const addressData = (await addressResponse.json()) as {
            is_verified?: boolean;
            name?: string;
        };

        if (!addressData.is_verified) {
            return emptyResult;
        }

        // Get source code
        const sourceUrl = `${baseApiUrl}/smart-contracts/${address}`;
        const sourceResponse = await fetch(sourceUrl);
        const sourceData = (await sourceResponse.json()) as {
            name?: string;
            source_code?: string;
            additional_sources?: Array<{
                file_path: string;
                source_code: string;
            }>;
        };

        if (!sourceData.source_code) {
            return emptyResult;
        }

        const contractName = sourceData.name || '';
        const allSources: Record<string, string> = {};

        // Main contract source
        if (contractName) {
            allSources[`contracts/${contractName}.sol`] = sourceData.source_code;
        }

        // Additional sources (dependencies)
        if (sourceData.additional_sources) {
            for (const src of sourceData.additional_sources) {
                allSources[src.file_path] = src.source_code;
            }
        }

        return {
            verified: true,
            contractName,
            sourceCode: sourceData.source_code,
            allSources,
        };
    } catch {
        return emptyResult;
    }
}

// Fetch source code from block explorer
async function fetchExplorerSource(
    address: string,
    networkName: string,
): Promise<ExplorerSourceResult> {
    const { apiUrl, apiKey, chainId, isV2, isBlockscout } = getExplorerApiConfig(networkName);

    const emptyResult: ExplorerSourceResult = {
        verified: false,
        contractName: '',
        sourceCode: null,
        allSources: {},
    };

    if (!apiUrl) {
        return emptyResult;
    }

    // Use Blockscout API if detected
    if (isBlockscout) {
        return fetchBlockscoutSource(address, apiUrl);
    }

    // Use Etherscan API format
    try {
        let url: string;
        if (isV2 && chainId) {
            url = `${apiUrl}?chainid=${chainId}&module=contract&action=getsourcecode&address=${address}&apikey=${apiKey}`;
        } else {
            url = `${apiUrl}?module=contract&action=getsourcecode&address=${address}&apikey=${apiKey}`;
        }

        const response = await fetch(url);
        const data = (await response.json()) as {
            status: string;
            result: Array<{
                SourceCode?: string;
                ContractName?: string;
                ABI?: string;
            }> | string;
            message?: string;
        };

        if (data.status !== '1' || !Array.isArray(data.result) || !data.result[0]) {
            return emptyResult;
        }

        const result = data.result[0];
        const sourceCode = result.SourceCode;
        const contractName = result.ContractName || '';

        if (!sourceCode || sourceCode === '') {
            return emptyResult;
        }

        // Parse source code - can be JSON (multi-file) or plain Solidity
        let allSources: Record<string, string> = {};
        let mainSource: string | null = null;

        // Check if it's JSON format (starts with {{ for standard-json-input)
        if (sourceCode.startsWith('{{')) {
            try {
                // Remove extra braces wrapper
                const jsonStr = sourceCode.slice(1, -1);
                const parsed = JSON.parse(jsonStr) as {
                    sources?: Record<string, { content: string }>;
                };
                if (parsed.sources) {
                    for (const [filePath, fileData] of Object.entries(parsed.sources)) {
                        allSources[filePath] = fileData.content;
                        // Find the main contract file
                        if (filePath.includes(contractName) || filePath.endsWith(`${contractName}.sol`)) {
                            mainSource = fileData.content;
                        }
                    }
                }
            } catch {
                // JSON parse failed, treat as plain source
                mainSource = sourceCode;
            }
        } else if (sourceCode.startsWith('{')) {
            // Single brace - might be sources object directly
            try {
                const parsed = JSON.parse(sourceCode) as Record<string, { content: string }>;
                for (const [filePath, fileData] of Object.entries(parsed)) {
                    if (fileData.content) {
                        allSources[filePath] = fileData.content;
                        if (filePath.includes(contractName)) {
                            mainSource = fileData.content;
                        }
                    }
                }
            } catch {
                mainSource = sourceCode;
            }
        } else {
            // Plain Solidity source
            mainSource = sourceCode;
        }

        return {
            verified: true,
            contractName,
            sourceCode: mainSource,
            allSources,
        };
    } catch {
        return emptyResult;
    }
}


// Normalize source code for comparison (remove whitespace differences, normalize line endings)
function normalizeSource(source: string): string {
    return source
        .replace(/\r\n/g, '\n') // Normalize line endings
        .replace(/\r/g, '\n')
        .trim();
}

// Compare source code from explorer with local source
async function compareSourceCode(
    explorerSources: Record<string, string>,
    contractName: string,
    localContractName: string,
    debug: boolean = false,
): Promise<'match' | 'mismatch' | 'unknown'> {
    const fs = await import('fs');
    const pathModule = await import('path');

    // Find the main contract source in explorer sources
    let explorerSource: string | null = null;
    let matchedPath: string | null = null;

    // Extract just the filename from path for exact matching
    const getFilename = (p: string) => p.split('/').pop() || p;

    for (const [filePath, content] of Object.entries(explorerSources)) {
        const filename = getFilename(filePath);
        // Exact filename match (not substring) - avoid matching IContract.sol when looking for Contract.sol
        if (
            filename === `${contractName}.sol` ||
            filename === `${localContractName}.sol`
        ) {
            explorerSource = content;
            matchedPath = filePath;
            break;
        }
    }

    if (debug) {
        console.log(`    Explorer sources: ${Object.keys(explorerSources).length} files`);
        console.log(`    Looking for: ${contractName}.sol or ${localContractName}.sol`);
        console.log(`    Matched path: ${matchedPath || 'NONE'}`);
    }

    if (!explorerSource) {
        if (debug) {
            console.log(`    Available paths: ${Object.keys(explorerSources).slice(0, 5).join(', ')}...`);
        }
        return 'unknown';
    }

    // Find local source file - search recursively in src/
    const srcRoot = pathModule.join(__dirname, '..', '..', 'src');
    let localSource: string | null = null;
    let localPath: string | null = null;

    const findFile = (dir: string, filename: string): string | null => {
        try {
            const entries = fs.readdirSync(dir, { withFileTypes: true });
            for (const entry of entries) {
                const fullPath = pathModule.join(dir, entry.name);
                if (entry.isDirectory()) {
                    const found = findFile(fullPath, filename);
                    if (found) return found;
                } else if (entry.name === filename) {
                    return fullPath;
                }
            }
        } catch {
            // Ignore errors
        }
        return null;
    };

    // Try local contract name first, then explorer contract name
    for (const name of [localContractName, contractName]) {
        localPath = findFile(srcRoot, `${name}.sol`);
        if (localPath) {
            localSource = fs.readFileSync(localPath, 'utf8');
            break;
        }
    }

    // Also check test/shared for testable contracts
    if (!localSource) {
        const testPath = pathModule.join(__dirname, '..', '..', 'test', 'shared', `${localContractName}.sol`);
        if (fs.existsSync(testPath)) {
            localSource = fs.readFileSync(testPath, 'utf8');
            localPath = testPath;
        }
    }

    if (debug) {
        console.log(`    Local path: ${localPath || 'NOT FOUND'}`);
    }

    if (!localSource) {
        return 'unknown';
    }

    // Normalize and compare
    const normalizedExplorer = normalizeSource(explorerSource);
    const normalizedLocal = normalizeSource(localSource);

    if (normalizedExplorer === normalizedLocal) {
        return 'match';
    }

    if (debug) {
        // Show first difference
        const expLines = normalizedExplorer.split('\n');
        const locLines = normalizedLocal.split('\n');
        for (let i = 0; i < Math.min(expLines.length, locLines.length); i++) {
            if (expLines[i] !== locLines[i]) {
                console.log(`    First diff at line ${i + 1}:`);
                console.log(`      Explorer: "${expLines[i].slice(0, 80)}"`);
                console.log(`      Local:    "${locLines[i].slice(0, 80)}"`);
                break;
            }
        }
        if (expLines.length !== locLines.length) {
            console.log(`    Line count: explorer=${expLines.length}, local=${locLines.length}`);
        }
    }

    return 'mismatch';
}

// Attempt to verify a contract on Etherscan
async function attemptVerification(
    address: string,
    contractName: string,
    constructorArgs: unknown[] = [],
): Promise<boolean> {
    try {
        console.log(`  Attempting to verify ${address} as ${contractName}...`);
        await hre.run('verify:verify', {
            address,
            constructorArguments: constructorArgs,
            contract: undefined, // Let hardhat figure out the contract
        });
        return true;
    } catch (error: unknown) {
        const errorMsg =
            error instanceof Error ? error.message : String(error);
        if (errorMsg.includes('Already Verified')) {
            return true;
        }
        console.log(`  Verification failed: ${errorMsg}`);
        return false;
    }
}

// Get constructor args for implementation contracts from OpenZeppelin manifest
async function getConstructorArgsFromManifest(
    implementationAddress: string,
): Promise<unknown[] | undefined> {
    try {
        const fs = await import('fs');
        const path = await import('path');

        const networkName = hre.network.name;
        const manifestPath = path.join(
            __dirname,
            '..',
            '..',
            '.openzeppelin',
            `${networkName}.json`,
        );

        if (!fs.existsSync(manifestPath)) {
            return undefined;
        }

        const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
        const impls = manifest.impls || {};

        for (const implData of Object.values(impls) as Array<{
            address: string;
            allAddresses?: string[];
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            layout?: any;
        }>) {
            if (
                implData.address?.toLowerCase() ===
                    implementationAddress.toLowerCase() ||
                implData.allAddresses?.some(
                    (a: string) =>
                        a.toLowerCase() === implementationAddress.toLowerCase(),
                )
            ) {
                // Found the implementation, but constructor args are in layout.types
                // For now, return empty - constructor args are usually immutables
                return [];
            }
        }
        return undefined;
    } catch {
        return undefined;
    }
}

async function main() {
    const networkName = hre.network.name;

    // Load env files: first generic .env (for ETHERSCAN_API_KEY), then network-specific
    dotenv.config({ path: path.join(__dirname, '..', '_env', '.env') });
    dotenv.config({ path: path.join(__dirname, '..', '_env', `.${networkName}.env`) });

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);

    // Get chain config (includes deployment mode)
    const chainConfig = getChainConfig(networkName);
    const deploymentMode = chainConfig.deploymentMode;

    let addresses: Record<string, AddressEntry>;
    try {
        addresses = addressFile.getContractAddresses() as Record<
            string,
            AddressEntry
        >;
    } catch (error) {
        console.error(`No deployment file found for network: ${networkName}`);
        process.exitCode = 1;
        return;
    }

    const autoVerify = process.env.AUTO_VERIFY !== 'false'; // enabled by default

    // Get explorer config
    const explorerConfig = getExplorerApiConfig(networkName);

    console.log(`Network: ${networkName} | Mode: ${deploymentMode} | Explorer: ${explorerConfig.explorerName}`);
    if (!explorerConfig.apiKey) {
        console.log('WARNING: No API key configured - verification checks may fail');
    }
    console.log();

    const results: ValidationResult[] = [];

    // Filter out metadata entries (network, startBlock at root level)
    const contractEntries = Object.entries(addresses).filter(
        ([name]) => !['network', 'startBlock'].includes(name),
    );

    console.log(`Checking ${contractEntries.length} contracts...`);

    for (const [name, entry] of contractEntries) {
        if (!entry || !entry.address) {
            continue;
        }

        const contractName = getContractName(name, deploymentMode);
        const isProxy = !!entry.proxyType;
        const proxyAddress = entry.address;
        let implementationAddress = entry.implementation || '';

        // For transparent proxies, get current implementation from chain
        if (entry.proxyType === 'TransparentProxy' && proxyAddress) {
            try {
                implementationAddress =
                    await upgrades.erc1967.getImplementationAddress(proxyAddress);
            } catch {
                // Keep the one from file
            }
        }

        // For beacon proxies, get implementation from beacon
        if (entry.proxyType === 'BeaconProxy' && proxyAddress) {
            try {
                implementationAddress =
                    await upgrades.beacon.getImplementationAddress(proxyAddress);
            } catch {
                // Keep the one from file
            }
        }

        const result: ValidationResult = {
            name,
            contractName,
            proxyAddress,
            implementationAddress,
            proxyType: entry.proxyType || 'none',
            bytecodeMatch: 'unknown',
            etherscanVerified: false,
            upgradeable: isProxy,
        };

        const addressToCheck = implementationAddress || proxyAddress;

        // Fetch verified source from explorer
        const explorerResult = await fetchExplorerSource(addressToCheck, networkName);
        result.etherscanVerified = explorerResult.verified;

        // Small delay to avoid rate limiting
        await new Promise((resolve) => setTimeout(resolve, 200));

        const debug = process.env.DEBUG === 'true';

        if (explorerResult.verified && Object.keys(explorerResult.allSources).length > 0) {
            // Compare source code from explorer with local source
            result.bytecodeMatch = await compareSourceCode(
                explorerResult.allSources,
                explorerResult.contractName,
                contractName,
                debug,
            );
        } else {
            // Not verified - can't compare source
            result.bytecodeMatch = 'unknown';

            // Try to verify if auto-verify is enabled
            if (autoVerify) {
                result.verificationAttempted = true;
                const constructorArgs = (await getConstructorArgsFromManifest(addressToCheck)) || [];
                result.verificationSuccess = await attemptVerification(addressToCheck, contractName, constructorArgs);
                if (result.verificationSuccess) {
                    result.etherscanVerified = true;
                }
            }
        }

        results.push(result);
    }

    // Categorize results
    const ok = results.filter((r) => r.bytecodeMatch === 'match' && r.etherscanVerified);
    const mismatched = results.filter((r) => r.bytecodeMatch === 'mismatch');
    const notVerified = results.filter((r) => !r.etherscanVerified);
    const unknown = results.filter((r) => r.bytecodeMatch === 'unknown' && r.etherscanVerified);

    console.log();
    console.log('='.repeat(60));

    // Show OK contracts
    if (ok.length > 0) {
        console.log(`\nOK (source matches & verified): ${ok.length}`);
        for (const r of ok) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            console.log(`  ✓ ${label}`);
        }
    }

    // Show mismatched contracts (source code differs)
    if (mismatched.length > 0) {
        console.log(`\nSOURCE MISMATCH: ${mismatched.length}`);
        for (const r of mismatched) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const addr = r.implementationAddress || r.proxyAddress;
            const canUpgrade = r.upgradeable ? '(can upgrade)' : '(needs redeploy)';
            console.log(`  ✗ ${label} ${canUpgrade}`);
            console.log(`    ${addr}`);
        }
    }

    // Show not verified
    if (notVerified.length > 0) {
        console.log(`\nNOT VERIFIED: ${notVerified.length}`);
        for (const r of notVerified) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const addr = r.implementationAddress || r.proxyAddress;
            console.log(`  ? ${label}`);
            console.log(`    ${addr}`);
        }
    }

    // Show unknown (verified but couldn't find local source)
    if (unknown.length > 0) {
        console.log(`\nUNKNOWN (local source not found): ${unknown.length}`);
        for (const r of unknown) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            console.log(`  ? ${label}`);
        }
    }

    console.log();
    console.log('='.repeat(60));
    console.log(`Summary: ${ok.length} OK, ${mismatched.length} source mismatch, ${notVerified.length} not verified, ${unknown.length} unknown`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
