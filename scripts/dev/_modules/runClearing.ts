import { Signer } from 'ethers';
import { doClearing } from '../../_modules/doClearing';
import { ClearingConfigurationStruct } from '../../../typechain-types/src/core/clearing/ClearingSteps';
import { calculateLoyaltyLevel } from '../../_modules/calculateLoyaltyLevel';
import { endClearing, startClearing } from './startEndClearing';
import { getCurrentEpochNumber } from '../../_modules/getCurrentEpochNumber';
import { repayPool } from '../../_modules/repayPool';

export async function runClearing(
    lendingPoolAddress: string,
    clearingConfiguration: ClearingConfigurationStruct,
    clearingManagerAccount: Signer,
    adminAccount: Signer,
    repayAmount = 0n,
    doEndClearing = false,
) {
    if (repayAmount > 0) {
        await repayPool(
            lendingPoolAddress,
            adminAccount,
            repayAmount,
            true,
            true,
        );
    }

    console.log('Manually start clearing period');
    await startClearing(adminAccount);

    console.log('Calculating loyalty level');
    await calculateLoyaltyLevel(10000, adminAccount);

    // run clearing
    const targetEpochNumber = await getCurrentEpochNumber(adminAccount);
    
    await doClearing(
        lendingPoolAddress,
        clearingManagerAccount,
        targetEpochNumber,
        clearingConfiguration,
    );

    // end clearing period
    if (doEndClearing) {
        console.log('Manually ending clearing period');
        await endClearing(adminAccount);
    }
}
