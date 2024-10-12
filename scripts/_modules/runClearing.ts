import { Signer } from 'ethers';
import { doClearing } from './doClearing';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';
import { calculateLoyaltyLevel } from './calculateLoyaltyLevel';
import { endClearing, starClearing } from './startEndClearing';
import { getCurrentEpochNumber } from './getCurrentEpochNumber';

export async function runClearing(
    lendingPoolAddress: string,
    clearingConfiguration: ClearingConfigurationStruct,
    clearingManagerAccount: Signer,
    adminAccount: Signer,
) {
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
    console.log('Manually ending clearing period');
    await endClearing(adminAccount);
}
