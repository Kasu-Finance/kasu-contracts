import { HardhatUserConfig, subtask } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import { glob } from 'glob';
import * as path from 'path';
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
    async (_, hre, runSuper) => {
        const paths = await runSuper();

        const testContracts = path.join(
            hre.config.paths.root,
            'test',
            'shared',
            'MockUSDC.sol',
        );
        const proxyAdmin = path.join(
            hre.config.paths.root,
            'lib',
            'openzeppelin-contracts',
            'contracts',
            'proxy',
            'ProxyAdmin.sol',
        );
        const testContractsPaths = glob.sync(testContracts);
        const proxyAdminPaths = glob.sync(proxyAdmin);

        return [...paths, ...testContractsPaths, ...proxyAdminPaths];
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
            live: false,
            saveDeployments: true,
            tags: ['local'],
        },
    },
    namedAccounts: {
        admin: 0,
        alice: 1,
        bob: 2,
    },
};

export default config;
