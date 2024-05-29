import { parseUnits } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { doClearing } from '../_modules/doClearing';
import { parseKasuError } from '../_utils/parseErrors';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';

const lendingPoolAddress = '0xb93c239690061228110525aa16622345241b388e';
const numberOfTranches = 3;
const drawAmount = parseUnits('0', 6);
const targetEpochNumber = 4n;

async function main() {
    const signers = await getAccounts(hre.network.name);
    const clearingManagerAccount = signers[1];
    const admin = signers[1];

    // overwrite clearing config - optional
    const ratios = [[100_00], [30_00, 70_00], [15_00, 35_00, 50_00]];

    const clearingConfiguration: ClearingConfigurationStruct = {
        drawAmount: drawAmount,
        trancheDesiredRatios: ratios[numberOfTranches - 1],
        maxExcessPercentage: 0, // 0%
        minExcessPercentage: 0, // 0%
    };

    // signers
    try {
        await doClearing(
            lendingPoolAddress,
            clearingManagerAccount,
            targetEpochNumber,
            clearingConfiguration,
        );
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
