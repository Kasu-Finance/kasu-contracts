import path from 'path';
import * as hre from 'hardhat';
import fs from 'fs';
import {
    ClearingManager__factory,
    SystemVariables__factory,
} from '../typechain-types';
import { ClearingConfigurationStruct } from '../typechain-types/src/core/clearing/ClearingManager';

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
    const clearingManager = ClearingManager__factory.connect(
        deploymentAddresses.ClearingManager.address,
        admin,
    );

    const systemVariables = SystemVariables__factory.connect(
        deploymentAddresses.SystemVariables.address,
        admin,
    );

    let tx;

    // overwrite clearing config - optional
    const lendingPoolAddress = '0x991d2d2791d42447FC4A20E1AD5Da87995217A26';
    const currentEpochNumber = await systemVariables.getCurrentEpochNumber();

    const clearingConfiguration: ClearingConfigurationStruct = {
        borrowAmount: 100_000_000_000, // 100K
        trancheDesiredRatios: [20_00, 30_00, 50_00], // 20%, 30%, 50%
        maxExcessPercentage: 10_00, // 10%
        minExcessPercentage: 0, // 0%
        isOverridden: true,
    };

    tx = await clearingManager.registerClearingConfig(
        lendingPoolAddress,
        currentEpochNumber,
        clearingConfiguration,
    );
    await tx.wait(1);

    // run clearing
    const pendingRequestsPriorityCalculationBatchSize = 10;
    const acceptedRequestsExecutionBatchSize = 10;

    tx = await clearingManager.doClearing(
        lendingPoolAddress,
        currentEpochNumber,
        pendingRequestsPriorityCalculationBatchSize,
        acceptedRequestsExecutionBatchSize,
    );
    await tx.wait(1);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
