import * as repl from 'node:repl';

import { addressFileFactory } from '../utils/_logs';
import { SystemVariablesTestable__factory } from '../../typechain-types';
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
const wallet = new ethers.Wallet(adminPK, provider);

export const systemVariablesTestableAdmin =
    SystemVariablesTestable__factory.connect(
        deploymentAddresses['SystemVariables'].address,
        wallet,
    );

const replServer = repl.start({
    prompt: 'Start interacting with KASU > ',
    useGlobal: true,
});

replServer.context.systemVariablesTestableAdmin = systemVariablesTestableAdmin;
