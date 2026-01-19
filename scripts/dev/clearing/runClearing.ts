import { runClearing } from '../_modules/runClearing';
import { parseUnits } from 'ethers';
import * as hre from 'hardhat';
import { getAccounts } from '../../_modules/getAccounts';
import { ClearingConfigurationStruct } from '../../../typechain-types/src/core/clearing/ClearingSteps';
import { parseKasuError } from '../../_utils/parseErrors';
import { requireLocalNetwork } from '../../_utils/env';

const lendingPoolAddress = '0xd48101baf608aea75c53f0ea462b3396e9a79dc0';
const drawAmount = parseUnits('10000', 6);
const repayAmount = parseUnits('0', 6);
const doEndClearing = false;

async function main() {
    requireLocalNetwork(hre.network.name);

    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];
    const clearingManagerAccount = signers[1];

    const clearingConfigurationEpoch1: ClearingConfigurationStruct = {
        drawAmount: drawAmount,
        trancheDesiredRatios: [20_00, 10_00, 70_00],
        maxExcessPercentage: 0,
        minExcessPercentage: 0,
    };

    await runClearing(
        lendingPoolAddress,
        clearingConfigurationEpoch1,
        clearingManagerAccount,
        adminAccount,
        repayAmount,
        doEndClearing,
    );
}

main().catch((error) => {
    console.error(error);
    parseKasuError(error);
    process.exitCode = 1;
});
