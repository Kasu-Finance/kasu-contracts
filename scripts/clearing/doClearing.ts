import { parseUnits } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { doClearing } from '../_modules/doClearing';
import { parseKasuError } from '../_utils/parseErrors';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';
import { requireEnv, requireEnvBigInt, requireEnvNumber } from '../_utils/env';

// Required environment variables:
// LENDING_POOL_ADDRESS - address of the lending pool
// NUMBER_OF_TRANCHES - number of tranches (1, 2, or 3)
// DRAW_AMOUNT - amount to draw in USDC units (e.g., "1000" for 1000 USDC)
// TARGET_EPOCH_NUMBER - target epoch number for clearing
const lendingPoolAddress = requireEnv('LENDING_POOL_ADDRESS');
const numberOfTranches = requireEnvNumber('NUMBER_OF_TRANCHES');
const drawAmount = parseUnits(requireEnv('DRAW_AMOUNT'), 6);
const targetEpochNumber = requireEnvBigInt('TARGET_EPOCH_NUMBER');

async function main() {
    const signers = await getAccounts(hre.network.name);
    const clearingManagerAccount = signers[1];

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
