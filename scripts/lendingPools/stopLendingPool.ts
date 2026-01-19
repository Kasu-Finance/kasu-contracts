import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import { LendingPoolManager__factory } from '../../typechain-types';
import { parseKasuError } from '../_utils/parseErrors';
import { ContractTransactionResponse } from 'ethers';
import { requireEnv } from '../_utils/env';

// Required environment variables:
// LENDING_POOL_ADDRESS - address of the lending pool to stop
const lendingPoolAddress = requireEnv('LENDING_POOL_ADDRESS');

async function main() {
    // file
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[0];

    // contracts
    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        admin,
    );

    let tx: ContractTransactionResponse;
    // interactions
    try {
        console.log('stopLendingPool...');
        tx = await lendingPoolManagerAdmin.stopLendingPool(lendingPoolAddress);
        await tx.wait();
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
