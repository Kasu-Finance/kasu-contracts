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
    /** Deployment mode: 'full' (with KSU token) or 'lite' (without token) */
    deploymentMode: 'full' | 'lite';
    /** Wrapped native token address (WETH, WXDC, etc.) */
    wrappedNativeAddress: string;
    /** USDC token address (or stablecoin equivalent) */
    usdcAddress: string;
    /** NexeraID signer address for KYC verification */
    nexeraIdSigner: string;
    /** Kasu multisig address for proxy ownership and ROLE_KASU_ADMIN */
    kasuMultisig: string;
    /** Pool manager multisig for ROLE_POOL_MANAGER and ROLE_POOL_FUNDS_MANAGER */
    poolManagerMultisig: string;
    /** Pool admin multisig for ROLE_LENDING_POOL_CREATOR, ROLE_POOL_ADMIN, ROLE_POOL_CLEARING_MANAGER */
    poolAdminMultisig: string;
    /** Protocol fee claimer address for ROLE_PROTOCOL_FEE_CLAIMER */
    protocolFeeClaimer: string;
    /** Protocol fee receiver address (receives protocol fees) */
    protocolFeeReceiver: string;
    /** Lending pool addresses (for smoke tests only - pool addresses are public on-chain) */
    lendingPoolAddresses: string[];
    /** Addresses that should NOT have admin roles (old admins that were revoked) */
    revokedAdminAddresses: string[];
    /** Whether this is a testnet */
    isTestnet: boolean;
    /** Whether Tenderly supports this chain for simulations */
    tenderlySupported: boolean;
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
        deploymentMode: 'lite',
        wrappedNativeAddress: '', // Will be set by env or deployment
        usdcAddress: '', // Will deploy MockUSDC
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '', // Local testing - no multisig
        poolManagerMultisig: '',
        poolAdminMultisig: '',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '', // Will default to admin address
        lendingPoolAddresses: [], // Pools will be created during testing
        revokedAdminAddresses: [],
        isTestnet: true,
        tenderlySupported: false,
    },
    hardhat: {
        name: 'Hardhat',
        chainId: 31337,
        deploymentMode: 'lite',
        wrappedNativeAddress: '',
        usdcAddress: '',
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '', // Local testing - no multisig
        poolManagerMultisig: '',
        poolAdminMultisig: '',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '', // Will default to admin address
        lendingPoolAddresses: [],
        revokedAdminAddresses: [],
        isTestnet: true,
        tenderlySupported: false,
    },

    // Base
    'base-sepolia': {
        name: 'Base Sepolia',
        chainId: 84532,
        deploymentMode: 'lite',
        wrappedNativeAddress: '0x4200000000000000000000000000000000000006',
        usdcAddress: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '', // Set via env for testnet
        poolManagerMultisig: '',
        poolAdminMultisig: '',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '', // Will default to admin address
        lendingPoolAddresses: [],
        revokedAdminAddresses: [],
        isTestnet: true,
        tenderlySupported: true,
    },
    base: {
        name: 'Base Mainnet',
        chainId: 8453,
        deploymentMode: 'full',
        wrappedNativeAddress: '0x4200000000000000000000000000000000000006',
        usdcAddress: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '0xC3128d734563E0d034d3ea177129657408C09D35',
        poolManagerMultisig: '0x39905d92Fc61643546D0940F97E5B5D0C0FB69F2',
        poolAdminMultisig: '0x7adf999af5E0617257014C94888cf98c4584E5E9',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        lendingPoolAddresses: [
            // Lending pools for smoke tests (public on-chain addresses)
            '0x03f93c8caa9a82e000d35673ba34a4c0e6e117a2',
            '0xc347a9e4aec8c8d11a149d2907deb2bf23b81c6f',
            '0xc987350716fe4a7d674c3591c391d29eba26b8ce',
            '0xB6DeAb2f712eFC9DF8c1E949b194BEE12F9C04FE', // Payment Finance
        ],
        revokedAdminAddresses: [
            // Old admin that should have DEFAULT_ADMIN_ROLE revoked
            '0x0e7e0a898ddBbE859d08976dE1673c7A9F579483',
        ],
        isTestnet: false,
        tenderlySupported: true,
    },

    // XDC Network
    xdc: {
        name: 'XDC Mainnet',
        chainId: 50,
        deploymentMode: 'lite',
        wrappedNativeAddress: '0x951857744785e80e2de051c32ee7b25f9c458c42', // WXDC
        usdcAddress: '0x9fe4e6321eeb7c4bc537570f015e4734b15002b8', // AUDD
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D',
        poolManagerMultisig: '0x21567eA21b14BEd14657e9725C2FE11C7be942B1',
        poolAdminMultisig: '0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        lendingPoolAddresses: [
            '0x20F42FB45f91657aCf9528b99a5a16d0229C7800',
            '0x3b7cb493Aa22f731DB2ab424D918e7375E00F6A9',
            '0xEDa50C91a8c4CA8A83652b8542c0b3BD00A71fad',
        ],
        revokedAdminAddresses: [], // Deployer checked separately
        isTestnet: false,
        tenderlySupported: false, // Tenderly doesn't support XDC
    },

    // Plume
    plume: {
        name: 'Plume Mainnet',
        chainId: 98866,
        deploymentMode: 'lite',
        wrappedNativeAddress: '0xEa237441c92CAe6FC17Caaf9a7acB3f953be4bd1', // WPLUME
        usdcAddress: '0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F',
        nexeraIdSigner: '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0',
        kasuMultisig: '0x344BA98De46750e0B7CcEa8c3922Db8A70391189',
        poolManagerMultisig: '0xEe2F38731F5050e02BF075d86DeBFb4B56F424fe',
        poolAdminMultisig: '0xEb8D4618713517C1367aCA4840b1fca3d8b090DF',
        protocolFeeClaimer: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        protocolFeeReceiver: '0xb925f1ecDAef927C88Ec69E5bdE779516DDdFF28',
        lendingPoolAddresses: [
            // Lending pools for smoke tests (public on-chain addresses)
            '0xB47Ee8770615E28dDDbCD3fC1bcAF11F2c1e732a',
            '0xf5c8E1E658855E116c656b1790Ef2B5951679764',
            '0xb742668ACced969b3CE64B4469E17F74A3E1d402',
        ],
        revokedAdminAddresses: [
            // Old admin that should have DEFAULT_ADMIN_ROLE revoked
            '0x0e7e0a898ddBbE859d08976dE1673c7A9F579483',
        ],
        isTestnet: false,
        tenderlySupported: false, // Tenderly doesn't support Plume
    },
};

/**
 * Get chain configuration for a network.
 * Falls back to env variables if chain is not in known configs.
 */
export function getChainConfig(networkName: string): ChainConfig {
    const config = CHAIN_CONFIGS[networkName];

    if (config) {
        // Parse lending pool addresses from env if provided (comma-separated)
        const envPoolAddresses = process.env.LENDING_POOL_ADDRESSES
            ? process.env.LENDING_POOL_ADDRESSES.split(',').map((addr) => addr.trim())
            : [];

        return {
            ...config,
            // Allow env overrides for any chain (except deploymentMode and protocolFeeReceiver)
            wrappedNativeAddress: process.env.WRAPPED_NATIVE_ADDRESS || config.wrappedNativeAddress,
            usdcAddress: process.env.USDC_ADDRESS || config.usdcAddress,
            nexeraIdSigner: process.env.NEXERA_ID_SIGNER || config.nexeraIdSigner,
            kasuMultisig: process.env.KASU_MULTISIG || config.kasuMultisig,
            poolManagerMultisig: process.env.POOL_MANAGER_MULTISIG || config.poolManagerMultisig,
            poolAdminMultisig: process.env.POOL_ADMIN_MULTISIG || config.poolAdminMultisig,
            protocolFeeClaimer: process.env.PROTOCOL_FEE_CLAIMER || config.protocolFeeClaimer,
            lendingPoolAddresses: envPoolAddresses.length > 0 ? envPoolAddresses : config.lendingPoolAddresses,
            // deploymentMode and protocolFeeReceiver are NOT overridable - they're chain-specific
        };
    }

    // Unknown chain - require all values from env
    const wrappedNativeAddress = process.env.WRAPPED_NATIVE_ADDRESS;
    const usdcAddress = process.env.USDC_ADDRESS;
    const nexeraIdSigner = process.env.NEXERA_ID_SIGNER;
    const kasuMultisig = process.env.KASU_MULTISIG;
    const poolManagerMultisig = process.env.POOL_MANAGER_MULTISIG;
    const poolAdminMultisig = process.env.POOL_ADMIN_MULTISIG;
    const protocolFeeClaimer = process.env.PROTOCOL_FEE_CLAIMER;
    const protocolFeeReceiver = process.env.PROTOCOL_FEE_RECEIVER;
    const deploymentMode = (process.env.DEPLOYMENT_MODE ?? 'lite').toLowerCase() as 'full' | 'lite';
    const lendingPoolAddresses = process.env.LENDING_POOL_ADDRESSES
        ? process.env.LENDING_POOL_ADDRESSES.split(',').map((addr) => addr.trim())
        : [];

    if (!wrappedNativeAddress) {
        throw new Error(
            `Unknown network "${networkName}" and WRAPPED_NATIVE_ADDRESS env not set. ` +
            `Either add chain to CHAIN_CONFIGS or set env variables.`
        );
    }

    return {
        name: networkName,
        chainId: 0, // Will be determined at runtime
        deploymentMode,
        wrappedNativeAddress,
        usdcAddress: usdcAddress || '',
        nexeraIdSigner: nexeraIdSigner || '',
        kasuMultisig: kasuMultisig || '',
        poolManagerMultisig: poolManagerMultisig || '',
        poolAdminMultisig: poolAdminMultisig || '',
        protocolFeeClaimer: protocolFeeClaimer || '',
        protocolFeeReceiver: protocolFeeReceiver || '',
        lendingPoolAddresses,
        revokedAdminAddresses: [],
        isTestnet: process.env.IS_TESTNET === 'true',
        tenderlySupported: false, // Unknown chains default to no Tenderly support
    };
}

/**
 * Check if a network is a local development network.
 */
export function isLocalNetwork(networkName: string): boolean {
    return networkName === 'localhost' || networkName === 'hardhat';
}
