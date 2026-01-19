import { LendingPoolManager__factory } from '../../typechain-types';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import { parseKasuError } from '../_utils/parseErrors';
import { requireEnv, requireEnvBigInt } from '../_utils/env';

// Required environment variables:
// LENDING_POOL_ADDRESS - address of the lending pool
// DESIRED_DRAW_AMOUNT - desired draw amount in raw units (e.g., 300000000000 for 300k USDC)
const LENDING_POOL = requireEnv('LENDING_POOL_ADDRESS');
const DESIRED_DRAW_AMOUNT = requireEnvBigInt('DESIRED_DRAW_AMOUNT');

async function main() {
    // contract addresses
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[0];

    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        admin,
    );

    try {
        await lendingPoolManagerAdmin.updateDesiredDrawAmount(
            LENDING_POOL,
            DESIRED_DRAW_AMOUNT,
        );
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
