import { LendingPoolManager__factory } from '../../typechain-types';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import { parseKasuError } from '../_utils/parseErrors';

const LENDING_POOL = '0x2f9c56edd3ba0a06aa58767f50e52761d85f3bc7';
const DESIRED_DRAW_AMOUNT = 300_000_000_000;

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
