import { parseUnits } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { doClearing } from '../_modules/doClearing';
import { parseKasuError } from '../_utils/parseErrors';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';

const lendingPoolAddress = '0xb93c239690061228110525aa16622345241b388e';
const numberOfTranches = 3;
const drawAmount = parseUnits('0', 6);
const targetEpochNumber = 4n;

async function main() {
    const signers = await getAccounts(hre.network.name);
    const clearingManagerAccount = signers[0];
    const admin = signers[1];

    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    try {
        await doClearing(
            lendingPoolAddress,
            drawAmount,
            clearingManagerAccount,
            numberOfTranches,
            targetEpochNumber,
        );
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
