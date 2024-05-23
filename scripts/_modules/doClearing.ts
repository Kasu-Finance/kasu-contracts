import { ethers, parseUnits, Signer } from 'ethers';
import * as hre from 'hardhat';
import { getLogFilePath } from '../_utils/addressFileFactory';
import fs from 'fs';
import { getAccounts } from './getAccounts';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
} from '../../typechain-types';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';

export async function doClearing(
    lendingPoolAddress: string,
    drawAmount: bigint,
    fromAccount: Signer,
    numberOfTranches: number,
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
    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        fromAccount,
    );

    const systemVariablesTestable = SystemVariablesTestable__factory.connect(
        deploymentAddresses.SystemVariables.address,
        admin,
    );

    let tx;

    // overwrite clearing config - optional
    const currentEpochNumber =
        await systemVariablesTestable.currentEpochNumber();

    const ratios = [[100_00], [30_00, 70_00], [15_00, 35_00, 50_00]];

    const clearingConfiguration: ClearingConfigurationStruct = {
        drawAmount: drawAmount,
        trancheDesiredRatios: ratios[numberOfTranches - 1],
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
}
