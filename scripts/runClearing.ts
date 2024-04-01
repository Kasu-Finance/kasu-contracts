import path from 'path';
import * as hre from 'hardhat';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
    UserManager__factory,
} from '../typechain-types';
import { ClearingConfigurationStruct } from '../typechain-types/src/core/clearing/ClearingManager';
import { ethers } from 'ethers';

const lendingPoolAddress = '0xEaCed9c07C0eC9cbABFA7aB081b6C55e8C2799a0';
const clearingDrawAmount = 400_000_000; // 400 USDC

async function main() {
    const deploymentAddressesPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(deploymentAddressesPath).toString(),
    );

    // signers
    const namedSigners = await hre.ethers.getNamedSigners();
    const admin = namedSigners['admin'];

    // contracts
    const userManager = UserManager__factory.connect(
        deploymentAddresses.UserManager.address,
        admin,
    );

    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        admin,
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
        await systemVariablesTestable.getCurrentEpochNumber();

    const clearingConfiguration: ClearingConfigurationStruct = {
        drawAmount: clearingDrawAmount, // 400 usdc
        trancheDesiredRatios: [20_00, 30_00, 50_00], // 20%, 30%, 50%
        maxExcessPercentage: 10_00, // 10%
        minExcessPercentage: 0, // 0%
        isOverridden: true,
    };

    console.log('Overwrite clearing config');
    tx = await lendingPoolManager.registerClearingConfig(
        lendingPoolAddress,
        currentEpochNumber,
        clearingConfiguration,
    );
    await tx.wait(1);

    // run clearing
    const pendingRequestsPriorityCalculationBatchSize = ethers.MaxUint256;
    const acceptedRequestsExecutionBatchSize = ethers.MaxUint256;

    console.log('Run clearing');
    tx = await lendingPoolManager.doClearing(
        lendingPoolAddress,
        currentEpochNumber,
        pendingRequestsPriorityCalculationBatchSize,
        acceptedRequestsExecutionBatchSize,
    );
    await tx.wait(1);

    // start clearing period
    console.log('Manually stop clearing period');
    tx = await systemVariablesTestable.endClearing();
    await tx.wait(1);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
