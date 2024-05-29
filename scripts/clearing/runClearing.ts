import { runClearing } from '../_modules/runClearing';
import { parseUnits } from 'ethers';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';

const lendingPoolAddress = '0xBf5A316F4303e13aE92c56D2D8C9F7629bEF5c6e';
const drawAmount = parseUnits('500', 6);

async function main() {
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];
    const clearingManagerAccount = signers[1];

    const clearingConfigurationEpoch1: ClearingConfigurationStruct = {
        drawAmount: drawAmount,
        trancheDesiredRatios: [20_00, 10_00, 70_00],
        maxExcessPercentage: 10_00,
        minExcessPercentage: 0,
    };

    await runClearing(
        lendingPoolAddress,
        clearingConfigurationEpoch1,
        clearingManagerAccount,
        adminAccount,
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
