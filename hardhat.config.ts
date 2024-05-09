import { HardhatUserConfig, subtask } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import * as dotenv from 'dotenv';
import path from 'path';
import { glob } from 'glob';
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';
import '@openzeppelin/hardhat-upgrades';

dotenv.config();

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
            'MockKsuPrice.sol',
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
        version: '0.8.23',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
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
            accounts: [
                process.env.DEPLOYER_KEY ||
                    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
                process.env.ADMIN_KEY ||
                '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
            ],
        },
    },
};

export default config;
