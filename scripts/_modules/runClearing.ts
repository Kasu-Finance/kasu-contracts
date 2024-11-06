import { Signer } from 'ethers';
import { doClearing } from './doClearing';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';
import { calculateLoyaltyLevel } from './calculateLoyaltyLevel';
import { endClearing, starClearing } from './startEndClearing';
import { getCurrentEpochNumber } from './getCurrentEpochNumber';
import { repayPool } from './repayPool';

export async function runClearing(
    lendingPoolAddress: string,
    clearingConfiguration: ClearingConfigurationStruct,
    clearingManagerAccount: Signer,
    adminAccount: Signer,
    repayAmount = 0n,
    doEndClearing = false,
) {
    if (repayAmount > 0) {
        await repayPool(lendingPoolAddress, adminAccount, repayAmount);
    }

    console.log('Manually start clearing period');
    await starClearing(adminAccount);

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
    if (!doEndClearing) {
        console.log('Manually ending clearing period');
        await endClearing(adminAccount);
    }
}
