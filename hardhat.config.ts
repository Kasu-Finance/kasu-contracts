import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import * as dotenv from 'dotenv';
dotenv.config();

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
        'base-testnet': {
            url: 'https://goerli.base.org',
            chainId: 84531,
            live: true,
            saveDeployments: true,
            tags: ['baseGoerli'],
            accounts: [
                process.env.DEPLOYER_KEY ||
                    '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
            ],
        },
    },
    namedAccounts: {
        admin: {
            default: 0,
            'base-testnet': 0,
        },
        alice: 1,
        bob: 2,
    },
    external: {
        contracts: [
            {
                artifacts: 'lib',
            },
            {
                artifacts: 'test/shared',
            },
        ],
    },
};

export default config;
