import * as hre from 'hardhat';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
    UserManager__factory,
} from '../../typechain-types';
import { ethers, Signer } from 'ethers';
import { getLogFilePath } from '../_utils/addressFileFactory';
import { getAccounts } from './getAccounts';
import { doClearing } from './doClearing';

export async function runClearing(
    lendingPoolAddress: string,
    drawAmount: bigint,
    fromAccount: Signer,
) {
    // config
    const { filePath } = getLogFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];

    // contracts
    const systemVariablesTestable = SystemVariablesTestable__factory.connect(
        deploymentAddresses.SystemVariables.address,
        admin,
    );

    const userManager = UserManager__factory.connect(
        deploymentAddresses.UserManager.address,
        admin,
    );

    let tx;

    // start clearing period
    console.log('Manually start clearing period');
    tx = await systemVariablesTestable.startClearing();
    await tx.wait(1);

    // overwrite clearing config - optional
    const calculateUserLoyaltyLevelsBatchSize = 10000;

    console.log('Calculate user loyalty levels');
    tx = await userManager.batchCalculateUserLoyaltyLevels(
        calculateUserLoyaltyLevelsBatchSize,
    );
    await tx.wait(1);

    // do clearing
    await doClearing(lendingPoolAddress, drawAmount, fromAccount, 3);

    // end clearing period
    console.log('Manually stop clearing period');
    tx = await systemVariablesTestable.endClearing();
    await tx.wait(1);
}
