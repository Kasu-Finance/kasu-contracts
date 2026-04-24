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
    // Primary check: stripped runtime bytecode (on-chain) vs local artifact deployedBytecode.
    // This is authoritative — whitespace/comment-only source changes don't affect it.
    bytecodeMatch: 'match' | 'mismatch' | 'unknown';
    // Secondary check: verified source on explorer vs local source file.
    // Strict (any whitespace diff fails) — used as a corroborating signal, not a blocker.
    sourceMatch: 'match' | 'mismatch' | 'unknown';
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

// Strip the Solidity metadata CBOR trailer from deployed bytecode. The last 2 bytes of the
// runtime bytecode encode the metadata length (big-endian uint16); everything from
// (end - metadataLen - 2 bytes) onward is the metadata blob. Stripping it leaves the pure
// executable bytecode, which is what we actually care about for "is this the same contract?"
// questions — it's deterministic for a given AST + compiler settings and is invariant to
// whitespace-only source changes (forge fmt, comment edits, etc.).
function stripMetadata(bytecode: string): string {
    const hex = bytecode.startsWith('0x') ? bytecode.slice(2) : bytecode;
    if (hex.length < 4) return hex;
    const metadataLen = parseInt(hex.slice(-4), 16);
    if (Number.isNaN(metadataLen) || metadataLen * 2 + 4 > hex.length) return hex;
    return hex.slice(0, hex.length - metadataLen * 2 - 4);
}

// Zero out immutable reference byte ranges. Solidity bakes immutable values (addresses,
// uint256s, etc.) into the runtime bytecode at deploy time, in slots whose byte offsets
// are recorded in the compiler's `immutableReferences` output. The local artifact has
// zero placeholders at those offsets; the on-chain copy has actual values. Comparing
// directly would always mismatch for any contract with immutables. Zeroing both sides
// at the known offsets gives an apples-to-apples code comparison.
//
// `refs` is keyed by AST node id; each entry is an array of {start, length} byte offsets
// within the RUNTIME bytecode (before metadata is appended).
function zeroImmutables(
    hexNoPrefix: string,
    refs: Record<string, Array<{ start: number; length: number }>>,
): string {
    if (!refs || Object.keys(refs).length === 0) return hexNoPrefix;
    const chars = hexNoPrefix.split('');
    for (const offsets of Object.values(refs)) {
        for (const { start, length } of offsets) {
            const charStart = start * 2;
            const charEnd = (start + length) * 2;
            for (let i = charStart; i < charEnd && i < chars.length; i++) {
                chars[i] = '0';
            }
        }
    }
    return chars.join('');
}

// Fetch immutableReferences for a contract from hardhat's build-info. Returns {} if
// none are defined (contract has no immutables) or build-info can't be located.
async function getImmutableReferences(
    contractName: string,
): Promise<Record<string, Array<{ start: number; length: number }>>> {
    try {
        const fqns = await hre.artifacts.getAllFullyQualifiedNames();
        const fqn = fqns.find((n) => n.endsWith(`:${contractName}`));
        if (!fqn) return {};
        const buildInfo = await hre.artifacts.getBuildInfo(fqn);
        if (!buildInfo) return {};
        const [sourceName] = fqn.split(':');
        const contractOutput =
            buildInfo.output?.contracts?.[sourceName]?.[contractName];
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const dbc = (contractOutput as any)?.evm?.deployedBytecode;
        if (!dbc || typeof dbc !== 'object') return {};
        return dbc.immutableReferences || {};
    } catch {
        return {};
    }
}

// Compare on-chain runtime bytecode against the local artifact's deployedBytecode, with the
// Solidity metadata CBOR trailer stripped from both. This is authoritative: if the executable
// bytes match, the deployed contract IS the compiled output of the current source (modulo
// whitespace-only changes that don't affect the AST).
//
// Returns 'match' if the stripped bytecodes are identical, 'mismatch' if they differ, or
// 'unknown' if either the on-chain code is empty (not a contract) or the local artifact
// can't be loaded.
async function compareBytecode(
    implementationAddress: string,
    contractName: string,
    debug: boolean = false,
): Promise<'match' | 'mismatch' | 'unknown'> {
    try {
        const onChainRaw = await hre.ethers.provider.getCode(implementationAddress);
        if (!onChainRaw || onChainRaw === '0x' || onChainRaw.length <= 2) {
            if (debug) console.log(`    No on-chain code at ${implementationAddress}`);
            return 'unknown';
        }

        let artifact;
        try {
            artifact = await hre.artifacts.readArtifact(contractName);
        } catch {
            if (debug) console.log(`    No local artifact for ${contractName}`);
            return 'unknown';
        }

        const localRaw = artifact.deployedBytecode;
        if (!localRaw || localRaw === '0x') {
            if (debug) console.log(`    Empty artifact deployedBytecode for ${contractName}`);
            return 'unknown';
        }

        const immutableRefs = await getImmutableReferences(contractName);
        const onChainStripped = zeroImmutables(
            stripMetadata(onChainRaw).toLowerCase(),
            immutableRefs,
        );
        const localStripped = zeroImmutables(
            stripMetadata(localRaw).toLowerCase(),
            immutableRefs,
        );

        if (onChainStripped === localStripped) {
            return 'match';
        }

        if (debug) {
            console.log(`    Bytecode mismatch for ${contractName}:`);
            console.log(`      on-chain length: ${onChainStripped.length}, local length: ${localStripped.length}`);
            // Find first differing byte offset for quick diagnosis
            const minLen = Math.min(onChainStripped.length, localStripped.length);
            for (let i = 0; i < minLen; i += 2) {
                if (onChainStripped[i] !== localStripped[i] || onChainStripped[i + 1] !== localStripped[i + 1]) {
                    console.log(`      first diff at byte ${i / 2}: on-chain=${onChainStripped.slice(i, i + 8)} local=${localStripped.slice(i, i + 8)}`);
                    break;
                }
            }
        }

        return 'mismatch';
    } catch (err) {
        if (debug) console.log(`    Bytecode comparison error: ${(err as Error).message}`);
        return 'unknown';
    }
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
            sourceMatch: 'unknown',
            etherscanVerified: false,
            upgradeable: isProxy,
        };

        const addressToCheck = implementationAddress || proxyAddress;
        const debug = process.env.DEBUG === 'true';

        // Primary check: on-chain runtime bytecode vs local artifact deployedBytecode (metadata stripped).
        // Authoritative — unaffected by whitespace/comment-only source changes.
        result.bytecodeMatch = await compareBytecode(addressToCheck, contractName, debug);

        // Secondary check: fetch verified source from explorer for source-level corroboration.
        const explorerResult = await fetchExplorerSource(addressToCheck, networkName);
        result.etherscanVerified = explorerResult.verified;

        // Small delay to avoid rate limiting
        await new Promise((resolve) => setTimeout(resolve, 200));

        if (explorerResult.verified && Object.keys(explorerResult.allSources).length > 0) {
            // Compare source code from explorer with local source (strict — flags whitespace diffs).
            result.sourceMatch = await compareSourceCode(
                explorerResult.allSources,
                explorerResult.contractName,
                contractName,
                debug,
            );
        } else if (autoVerify) {
            // Not verified - try to verify if auto-verify is enabled
            result.verificationAttempted = true;
            const constructorArgs = (await getConstructorArgsFromManifest(addressToCheck)) || [];
            result.verificationSuccess = await attemptVerification(addressToCheck, contractName, constructorArgs);
            if (result.verificationSuccess) {
                result.etherscanVerified = true;
            }
        }

        results.push(result);
    }

    // Categorize results
    // Authoritative pass condition: on-chain bytecode matches local artifact. Explorer verification
    // is a separate concern (public transparency), tracked but not gating.
    const bytecodeOk = results.filter((r) => r.bytecodeMatch === 'match');
    const bytecodeMismatch = results.filter((r) => r.bytecodeMatch === 'mismatch');
    const bytecodeUnknown = results.filter((r) => r.bytecodeMatch === 'unknown');
    const sourceDrift = results.filter(
        (r) => r.bytecodeMatch === 'match' && r.sourceMatch === 'mismatch',
    );
    const notVerified = results.filter((r) => !r.etherscanVerified);

    console.log();
    console.log('='.repeat(60));

    // Show OK contracts (bytecode match)
    if (bytecodeOk.length > 0) {
        console.log(`\nOK (bytecode matches): ${bytecodeOk.length}`);
        for (const r of bytecodeOk) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const verifiedMark = r.etherscanVerified ? '' : ' [NOT VERIFIED ON EXPLORER]';
            const driftMark = r.sourceMatch === 'mismatch'
                ? ' [explorer source is stale — re-verify with AUTO_VERIFY=true to refresh]'
                : '';
            console.log(`  ✓ ${label}${verifiedMark}${driftMark}`);
        }
    }

    // Show mismatched contracts (bytecode actually differs — real regression)
    if (bytecodeMismatch.length > 0) {
        console.log(`\nBYTECODE MISMATCH: ${bytecodeMismatch.length}`);
        for (const r of bytecodeMismatch) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const addr = r.implementationAddress || r.proxyAddress;
            const canUpgrade = r.upgradeable ? '(can upgrade)' : '(needs redeploy)';
            console.log(`  ✗ ${label} ${canUpgrade}`);
            console.log(`    ${addr}`);
        }
    }

    // Show unknown (couldn't load artifact or no on-chain code)
    if (bytecodeUnknown.length > 0) {
        console.log(`\nBYTECODE UNKNOWN (artifact missing or no on-chain code): ${bytecodeUnknown.length}`);
        for (const r of bytecodeUnknown) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const addr = r.implementationAddress || r.proxyAddress;
            console.log(`  ? ${label}`);
            console.log(`    ${addr}`);
        }
    }

    // Show source drift (bytecode fine, but explorer source is stale — e.g. post-fmt).
    if (sourceDrift.length > 0) {
        console.log(`\nSOURCE DRIFT (bytecode OK but explorer source out of date): ${sourceDrift.length}`);
        for (const r of sourceDrift) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            console.log(`  ~ ${label} — re-verify with AUTO_VERIFY=true to refresh`);
        }
    }

    // Show not verified on explorer (public transparency concern, not a correctness concern).
    if (notVerified.length > 0) {
        console.log(`\nNOT VERIFIED ON EXPLORER: ${notVerified.length}`);
        for (const r of notVerified) {
            const label = r.contractName !== r.name ? `${r.name} (${r.contractName})` : r.name;
            const addr = r.implementationAddress || r.proxyAddress;
            console.log(`  ? ${label}`);
            console.log(`    ${addr}`);
        }
    }

    console.log();
    console.log('='.repeat(60));
    console.log(
        `Summary: ${bytecodeOk.length} bytecode OK, ${bytecodeMismatch.length} bytecode mismatch, `
        + `${bytecodeUnknown.length} unknown, ${sourceDrift.length} source drift, ${notVerified.length} not verified`,
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
