import {
    ksuBonusMultiplier180,
    ksuBonusMultiplier30,
    ksuBonusMultiplier360,
    ksuBonusMultiplier720,
    lockMultiplier180,
    lockMultiplier30,
    lockMultiplier360,
    lockMultiplier720,
    lockPeriod180,
    lockPeriod30,
    lockPeriod360,
    lockPeriod720,
} from '../deploy';
import { KSULocking } from '../../typechain-types';
import { ContractTransactionResponse } from 'ethers';

export async function addLockPeriods(
    ksuLocking: KSULocking,
    ksuLockBonusDeploymentAddress: string,
) {
    let tx: ContractTransactionResponse;

    tx = await ksuLocking.setKSULockBonus(ksuLockBonusDeploymentAddress);
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod30,
        lockMultiplier30,
        ksuBonusMultiplier30,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod180,
        lockMultiplier180,
        ksuBonusMultiplier180,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod360,
        lockMultiplier360,
        ksuBonusMultiplier360,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod720,
        lockMultiplier720,
        ksuBonusMultiplier720,
    );
    await tx.wait(1);
}
