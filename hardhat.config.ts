import { HardhatUserConfig, subtask } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import path from 'path';
import { glob } from 'glob';
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';
import '@nomicfoundation/hardhat-verify';
import '@openzeppelin/hardhat-upgrades';
import "hardhat-contract-sizer";

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
            "src/core/lendingPool/PendingPool.sol": {
                version: "0.8.23",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            }
        }
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
    },
    etherscan: {
        apiKey: {
            base: 'YOUR_API_KEY',
        },
    },
};

export default config;
