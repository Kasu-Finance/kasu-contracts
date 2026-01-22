/**
 * Chain-specific configuration for Kasu deployments.
 *
 * This configuration is extensible - add new chains as needed.
 * All addresses should be checksummed.
 */

export interface ChainConfig {
    /** Human-readable chain name */
    name: string;
    /** Chain ID */
    chainId: number;
    /** Wrapped native token address (WETH, WXDC, etc.) */
    wrappedNativeAddress: string;
    /** USDC token address (or stablecoin equivalent) */
    usdcAddress: string;
    /** NexeraID signer address for KYC verification */
    nexeraIdSigner: string;
    /** Whether this is a testnet */
    isTestnet: boolean;
}

/**
 * Known chain configurations.
 *
 * To add a new chain:
 * 1. Add the chain config here
 * 2. Add the network to hardhat.config.ts
 * 3. Set up deployment addresses file in .openzeppelin/
 */
export const CHAIN_CONFIGS: Record<string, ChainConfig> = {
    // Local development
    localhost: {
        name: 'Localhost',
        chainId: 31337,
        wrappedNativeAddress: '', // Will be set by env or deployment
        usdcAddress: '', // Will deploy MockUSDC
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: true,
    },
    hardhat: {
        name: 'Hardhat',
        chainId: 31337,
        wrappedNativeAddress: '',
        usdcAddress: '',
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: true,
    },

    // Base
    'base-sepolia': {
        name: 'Base Sepolia',
        chainId: 84532,
        wrappedNativeAddress: '0x4200000000000000000000000000000000000006',
        usdcAddress: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: true,
    },
    base: {
        name: 'Base Mainnet',
        chainId: 8453,
        wrappedNativeAddress: '0x4200000000000000000000000000000000000006',
        usdcAddress: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: false,
    },

    // XDC Network
    xdc: {
        name: 'XDC Mainnet',
        chainId: 50,
        wrappedNativeAddress: '0x951857744785e80e2de051c32ee7b25f9c458c42', // WXDC
        usdcAddress: '0xfa2958cb79b0491cc627c1557f441ef849ca8eb1',
        nexeraIdSigner: '',
        isTestnet: false,
    },

    // Plume
    plume: {
        name: 'Plume Mainnet',
        chainId: 98866,
        wrappedNativeAddress: '', // Set via env
        usdcAddress: '', // Set via env
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: false,
    },
};

/**
 * Get chain configuration for a network.
 * Falls back to env variables if chain is not in known configs.
 */
export function getChainConfig(networkName: string): ChainConfig {
    const config = CHAIN_CONFIGS[networkName];

    if (config) {
        return {
            ...config,
            // Allow env overrides for any chain
            wrappedNativeAddress: process.env.WRAPPED_NATIVE_ADDRESS || config.wrappedNativeAddress,
            usdcAddress: process.env.USDC_ADDRESS || config.usdcAddress,
            nexeraIdSigner: process.env.NEXERA_ID_SIGNER || config.nexeraIdSigner,
        };
    }

    // Unknown chain - require all values from env
    const wrappedNativeAddress = process.env.WRAPPED_NATIVE_ADDRESS;
    const usdcAddress = process.env.USDC_ADDRESS;
    const nexeraIdSigner = process.env.NEXERA_ID_SIGNER;

    if (!wrappedNativeAddress) {
        throw new Error(
            `Unknown network "${networkName}" and WRAPPED_NATIVE_ADDRESS env not set. ` +
            `Either add chain to CHAIN_CONFIGS or set env variables.`
        );
    }

    return {
        name: networkName,
        chainId: 0, // Will be determined at runtime
        wrappedNativeAddress,
        usdcAddress: usdcAddress || '',
        nexeraIdSigner: nexeraIdSigner || '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        isTestnet: process.env.IS_TESTNET === 'true',
    };
}

/**
 * Check if a network is a local development network.
 */
export function isLocalNetwork(networkName: string): boolean {
    return networkName === 'localhost' || networkName === 'hardhat';
}
