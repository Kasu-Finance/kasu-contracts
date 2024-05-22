import * as repl from 'node:repl';

import { addressFileFactory } from '../_utils/addressFileFactory';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
    UserManager__factory,
} from '../../typechain-types';
import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

const networkName = process.env.NETWORK_NAME ?? 'localhost';

// dot env
dotenv.config({ path: `${__dirname}/.${networkName}.env` });
const jsonRpcUrl = process.env.JSON_RPC_URL ?? '';
const adminPK = process.env.ADMIN_PK ?? '';

const addressFile = addressFileFactory(0, networkName);
const deploymentAddresses = addressFile.getContractAddresses();

// json rpc
const provider = new ethers.JsonRpcProvider(jsonRpcUrl);
const adminWallet = new ethers.Wallet(adminPK, provider);

// contracts
export const systemVariablesTestableAdmin =
    SystemVariablesTestable__factory.connect(
        deploymentAddresses['SystemVariables'].address,
        adminWallet,
    );

const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
    deploymentAddresses.LendingPoolManager.address,
    adminWallet,
);

const userManagerAdmin = UserManager__factory.connect(
    deploymentAddresses.UserManager.address,
    adminWallet,
);

const replServer = repl.start({
    prompt: '>',
    useGlobal: true,
});

const help = [
    'systemVariablesTestableAdmin',
    'lendingPoolManager',
    'adminWallet',
];

replServer.context.help = help;
replServer.context.systemVariablesTestableAdmin = systemVariablesTestableAdmin;
replServer.context.lendingPoolManagerAdmin = lendingPoolManagerAdmin;
replServer.context.userManagerAdmin = userManagerAdmin;
