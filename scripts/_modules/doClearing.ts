import { ethers, parseUnits, Signer } from 'ethers';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import { getAccounts } from './getAccounts';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
} from '../../typechain-types';
import { ClearingConfigurationStruct } from '../../typechain-types/src/core/clearing/ClearingSteps';

export async function doClearing(
    lendingPoolAddress: string,
    clearingManagerAccount: Signer,
    targetEpochNumber: bigint,
    clearingConfiguration: ClearingConfigurationStruct,
    isConfigOverridden = true,
) {
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // contracts
    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        clearingManagerAccount,
    );

    let tx;

    // run clearing
    const pendingRequestsPriorityCalculationBatchSize = ethers.MaxUint256;
    const acceptedRequestsExecutionBatchSize = ethers.MaxUint256;

    console.log(
        `running clearing for lending pool `,
        lendingPoolAddress,
        `draw amount in USDC `,
        clearingConfiguration.drawAmount,
    );
    tx = await lendingPoolManager.doClearing(
        lendingPoolAddress,
        targetEpochNumber,
        pendingRequestsPriorityCalculationBatchSize,
        acceptedRequestsExecutionBatchSize,
        clearingConfiguration,
        isConfigOverridden,
    );
    await tx.wait(1);
}
