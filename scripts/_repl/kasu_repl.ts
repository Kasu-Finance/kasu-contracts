import * as repl from 'node:repl';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import {
    KasuAllowList__factory,
    KasuController__factory,
    LendingPool,
    LendingPool__factory,
    LendingPoolManager__factory,
    MockUSDC__factory,
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

const addressFile = deploymentFileFactory(networkName, 0);
const deploymentAddresses = addressFile.getContractAddresses();

// REPL Config
const replServer = repl.start({
    prompt: '>',
    useGlobal: true,
});

// json rpc
const provider = new ethers.JsonRpcProvider(jsonRpcUrl);
const adminWallet = new ethers.Wallet(adminPK, provider);

// contracts
export const mockUsdc = MockUSDC__factory.connect(
    deploymentAddresses.USDC.address,
    adminWallet,
);

export const systemVariablesTestableAdmin =
    SystemVariablesTestable__factory.connect(
        deploymentAddresses.SystemVariables.address,
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

const kasuControllerAdmin = KasuController__factory.connect(
    deploymentAddresses.KasuController.address,
    adminWallet,
);

const kasuAllowListAdmin = KasuAllowList__factory.connect(
    deploymentAddresses.KasuAllowList.address,
    adminWallet,
);

const connectToLendingPool = (lendingPoolAddress: string): LendingPool => {
    return LendingPool__factory.connect(lendingPoolAddress, adminWallet);
};

const help = [
    'systemVariablesTestableAdmin',
    'lendingPoolManager',
    'adminWallet',
];

replServer.context.help = help;
replServer.context.mockUsdc = mockUsdc;
replServer.context.systemVariablesTestableAdmin = systemVariablesTestableAdmin;
replServer.context.lendingPoolManagerAdmin = lendingPoolManagerAdmin;
replServer.context.userManagerAdmin = userManagerAdmin;
replServer.context.kasuControllerAdmin = kasuControllerAdmin;
replServer.context.kasuAllowListAdmin = kasuAllowListAdmin;
replServer.context.connectToLendingPool = connectToLendingPool;
replServer.context.ethers = ethers;
