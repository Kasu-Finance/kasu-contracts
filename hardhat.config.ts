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
            'src/core/lendingPool/PendingPool.sol': {
                version: '0.8.23',
                settings: {
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
            url: 'https://mainnet.base.org',
            chainId: 8453,
        },
        xdc: {
            url: process.env.XDC_RPC_URL ?? 'https://rpc.xdc.org',
            chainId: 50,
        },
        plume: {
            url: process.env.PLUME_RPC_URL ?? 'https://rpc.plumenetwork.xyz',
            chainId: 98866,
        },
    },
    etherscan: {
        // Etherscan V2 Multichain API - single key works for all supported chains
        // See supported chains: https://docs.etherscan.io/supported-chains
        apiKey: {
            // All Etherscan V2 supported chains use the same API key
            mainnet: process.env.ETHERSCAN_API_KEY ?? '',
            base: process.env.ETHERSCAN_API_KEY ?? '',
            baseSepolia: process.env.ETHERSCAN_API_KEY ?? '',
            xdc: process.env.ETHERSCAN_API_KEY ?? '',
            // Non-Etherscan explorers need separate keys
            plume: process.env.PLUME_SCAN_API_KEY ?? '',
        },
        customChains: [
            {
                network: 'xdc',
                chainId: 50,
                urls: {
                    apiURL: 'https://api.xdcscan.io/api',
                    browserURL: 'https://xdcscan.io',
                },
            },
            {
                network: 'plume',
                chainId: 98866,
                urls: {
                    apiURL: 'https://phoenix-explorer.plumenetwork.xyz/api',
                    browserURL: 'https://phoenix-explorer.plumenetwork.xyz',
                },
            },
        ],
    },
};

export default config;
