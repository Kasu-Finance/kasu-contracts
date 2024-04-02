import path from 'path';
import * as hre from 'hardhat';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    SystemVariablesTestable__factory,
    UserManager__factory,
} from '../typechain-types';
import { ethers } from 'ethers';
import { ClearingConfigurationStruct } from '../typechain-types/src/core/clearing/ClearingSteps';


const POOL_CLEARING_MANAGER_PK = "";

const LENDING_POOL_ADDRESS = '0x270169E35502A1d3637b562fEc0b69027b79C83b';
const DRAW_AMOUNT = hre.ethers.parseUnits("2500", 6); // 2500 USDC

console.log(`running clearing for lending pool: ${LENDING_POOL_ADDRESS}, draw amount: ${hre.ethers.formatUnits(DRAW_AMOUNT, 6)} USDC`);

async function main() {
    const deploymentAddressesPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(deploymentAddressesPath).toString(),
    );

    const clearingManager = new hre.ethers.Wallet(POOL_CLEARING_MANAGER_PK, hre.ethers.provider);

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
        clearingManager,
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
        drawAmount: DRAW_AMOUNT,
        trancheDesiredRatios: [20_00, 30_00, 50_00], // 20%, 30%, 50%
        maxExcessPercentage: 0, // 10%
        minExcessPercentage: 0, // 0%
        isOverridden: true,
    };

    console.log('Overwrite clearing config');
    tx = await lendingPoolManager.registerClearingConfig(
        LENDING_POOL_ADDRESS,
        currentEpochNumber,
        clearingConfiguration,
    );
    await tx.wait(1);

    // run clearing
    const pendingRequestsPriorityCalculationBatchSize = ethers.MaxUint256;
    const acceptedRequestsExecutionBatchSize = ethers.MaxUint256;

    console.log('Run clearing');
    tx = await lendingPoolManager.doClearing(
        LENDING_POOL_ADDRESS,
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
