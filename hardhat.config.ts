import { HardhatUserConfig, subtask } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import path from 'path';
import { glob } from 'glob';
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';
import '@nomicfoundation/hardhat-verify';
import '@openzeppelin/hardhat-upgrades';
import "hardhat-contract-sizer";
import * as dotenv from 'dotenv';

// Load generic .env file for shared config (ETHERSCAN_API_KEY, etc.)
dotenv.config({ path: path.join(__dirname, 'scripts', '_env', '.env') });

// Helper to load network-specific accounts
function getNetworkAccounts(networkName: string): string[] {
    // Try to load network-specific env file
    const envPath = path.join(__dirname, 'scripts', '_env', `.${networkName}.env`);
    try {
        const result = dotenv.config({ path: envPath });
        if (result.parsed) {
            const accounts: string[] = [];
            if (result.parsed.DEPLOYER_KEY) accounts.push(result.parsed.DEPLOYER_KEY);
            if (result.parsed.ADMIN_KEY && result.parsed.ADMIN_KEY !== result.parsed.DEPLOYER_KEY) {
                accounts.push(result.parsed.ADMIN_KEY);
            }
            return accounts;
        }
    } catch (e) {
        // Env file doesn't exist, return empty array
    }
    return [];
}

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
    async (_, hre, runSuper) => {
        const paths = await runSuper();

        const mockUSDC = path.join(
            hre.config.paths.root,
            'test',
            'shared',
            'MockUSDC.sol',
        );
        const mockKsuPrice = path.join(
            hre.config.paths.root,
            'test',
            'shared',
            'ManualKsuPrice.sol',
        );
        const dependenciesFix = path.join(
            hre.config.paths.root,
            'test',
            'shared',
            'DependenciesFix.sol',
        );
        const systemVariablesTestable = path.join(
            hre.config.paths.root,
            'test',
            'shared',
            'SystemVariablesTestable.sol',
        );

        const mockUSDCPath = glob.sync(mockUSDC);
        const mockKsuPricePath = glob.sync(mockKsuPrice);
        const dependenciesFixPath = glob.sync(dependenciesFix);
        const systemVariablesTestablePath = glob.sync(systemVariablesTestable);

        return [
            ...paths,
            ...mockUSDCPath,
            ...mockKsuPricePath,
            ...dependenciesFixPath,
            ...systemVariablesTestablePath,
        ];
    },
);

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: '0.8.23',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 800,
                    },
                },
            },
        ],
        overrides: {
            // PendingPool grew past EIP-170 after the FV-01 budget-tracking fix. via_ir's
            // yul-based pipeline shrinks it back under 24576 bytes. Matches foundry.toml.
            'src/core/lendingPool/PendingPool.sol': {
                version: '0.8.23',
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        },
    },
    networks: {
        localhost: {
            url: 'http://127.0.0.1:8545/',
            chainId: 31337,
        },
        'base-sepolia': {
            url: 'https://sepolia.base.org',
            chainId: 84532,
        },
        base: {
            url: process.env.BASE_RPC_URL || 'https://mainnet.base.org',
            chainId: 8453,
            accounts: getNetworkAccounts('base'),
        },
        xdc: {
            url: process.env.XDC_RPC_URL ?? 'https://rpc.xdc.org',
            chainId: 50,
            accounts: getNetworkAccounts('xdc'),
        },
        'xdc-usdc': {
            url: process.env.XDC_RPC_URL ?? 'https://rpc.xdc.org',
            chainId: 50,
            accounts: getNetworkAccounts('xdc-usdc'),
        },
        plume: {
            url: process.env.PLUME_RPC_URL ?? 'https://rpc.plume.org',
            chainId: 98866,
            accounts: getNetworkAccounts('plume'),
        },
    },
    etherscan: {
        // Etherscan V2 Multichain API — pass a single key at the top level.
        // Object-form `apiKey: { <network>: ... }` forces hardhat-verify onto the
        // deprecated V1 endpoint (decommissioned 2025-05-31) and verification
        // fails with "You are using a deprecated V1 endpoint".
        // Plume is Blockscout (not Etherscan) — its customChain apiURL below
        // receives this same key; Blockscout accepts empty/any key.
        apiKey: process.env.ETHERSCAN_API_KEY ?? '',
        customChains: [
            {
                network: 'xdc',
                chainId: 50,
                urls: {
                    apiURL: 'https://api.etherscan.io/v2/api?chainid=50',
                    browserURL: 'https://xdcscan.com/',
                },
            },
            {
                network: 'plume',
                chainId: 98866,
                urls: {
                    // Blockscout exposes an Etherscan-compat API at /api; hardhat-verify
                    // 2.x doesn't speak the REST-style /api/v2 shape, so point here.
                    apiURL: 'https://explorer.plume.org/api',
                    browserURL: 'https://explorer.plume.org/',
                },
            },
        ],
    },
};

export default config;
