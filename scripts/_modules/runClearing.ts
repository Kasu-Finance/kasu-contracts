import * as hre from 'hardhat';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
    UserManager__factory,
} from '../../typechain-types';
import { ethers, Signer } from 'ethers';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';
import { getLogFilePath } from '../_utils/addressFileFactory';
import { getAccounts } from './getAccounts';

export async function runClearing(
    lendingPoolAddress: string,
    drawAmount: bigint,
    fromAccount: Signer,
) {
    console.log(
        `running clearing for lending pool: ${lendingPoolAddress}, draw amount: ${hre.ethers.formatUnits(
            drawAmount,
            6,
        )} USDC`,
    );

    const { filePath } = getLogFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];

    // contracts
    const userManager = UserManager__factory.connect(
        deploymentAddresses.UserManager.address,
        admin,
    );

    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        fromAccount,
    );

    const systemVariablesTestable = SystemVariablesTestable__factory.connect(
        deploymentAddresses.SystemVariables.address,
        admin,
    );

    let tx;

    // start clearing period
    console.log('Manually start clearing period');
    tx = await systemVariablesTestable.startClearing();
    await tx.wait(1);

    // overwrite clearing config - optional
    const calculateUserLoyaltyLevelsBatchSize = 10000;

    console.log('Calculate user loyalty levels');
    tx = await userManager.batchCalculateUserLoyaltyLevels(
        calculateUserLoyaltyLevelsBatchSize,
    );
    await tx.wait(1);

    // overwrite clearing config - optional
    const currentEpochNumber =
        await systemVariablesTestable.currentEpochNumber();

    const clearingConfiguration: ClearingConfigurationStruct = {
        drawAmount: drawAmount,
        trancheDesiredRatios: [20_00, 30_00, 50_00], // 20%, 30%, 50%
        maxExcessPercentage: 0, // 10%
        minExcessPercentage: 0, // 0%
    };

    // run clearing
    const pendingRequestsPriorityCalculationBatchSize = ethers.MaxUint256;
    const acceptedRequestsExecutionBatchSize = ethers.MaxUint256;

    console.log('Run clearing');
    tx = await lendingPoolManager.doClearing(
        lendingPoolAddress,
        currentEpochNumber,
        pendingRequestsPriorityCalculationBatchSize,
        acceptedRequestsExecutionBatchSize,
        clearingConfiguration,
        true,
    );
    await tx.wait(1);

    // end clearing period
    console.log('Manually stop clearing period');
    tx = await systemVariablesTestable.endClearing();
    await tx.wait(1);
}
