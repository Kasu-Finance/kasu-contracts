/**
 * Recovery script for XDC USDC deployment.
 *
 * Context: The initial deploy_1.ts run on mainnet failed when calling
 * SystemVariables.initialize() because we passed a past timestamp
 * (1717653600 = Thu 6 Jun 2024 06:00 UTC, aligned with XDC AUDD) that the
 * production impl's initialize rejects (requires timestamp within the
 * current epoch, i.e. last 1 week).
 *
 * This script:
 *   1. Upgrades the SystemVariables proxy to SystemVariablesMigration
 *      (identical impl minus the past-timestamp check) with an atomic
 *      upgradeAndCall that runs initialize() with the aligned timestamp.
 *   2. Verifies the state was written correctly.
 *   3. Upgrades the SystemVariables proxy BACK to the production
 *      SystemVariables impl so the on-chain impl matches XDC AUDD.
 *   4. Initializes KasuPoolExternalTVL (was never reached by the failed
 *      deploy_1 run).
 *
 * After running this, continue with deploy_2.ts to grant roles to multisigs.
 *
 * Usage:
 *   npx hardhat --network xdc-usdc run scripts/recovery/finishXdcUsdcInit.ts
 */

import hre, { ethers, upgrades } from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { deployOptions } from '../_utils/deployFactory';
import { getAccounts } from '../_modules/getAccounts';
import { getChainConfig } from '../_config/chains';
import {
    SystemVariables__factory,
    KasuPoolExternalTVL__factory,
} from '../../typechain-types';
import { SystemVariablesSetupStruct } from '../../typechain-types/src/core/SystemVariables';

async function main() {
    const networkName = hre.network.name;
    if (networkName !== 'xdc-usdc') {
        throw new Error(
            `This recovery script is only for xdc-usdc. Got network: ${networkName}`,
        );
    }

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);

    const chainConfig = getChainConfig(networkName);
    const signers = await getAccounts(networkName);
    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();
    const adminSigner = signers[1];

    const alignedEpochStart = chainConfig.initialEpochStartTimestamp;
    if (!alignedEpochStart) {
        throw new Error('chainConfig.initialEpochStartTimestamp not set');
    }

    const systemVariablesProxy = addressFile.getContractAddress('SystemVariables');
    const ksuPriceProxy = addressFile.getContractAddress('KsuPrice');
    const kasuControllerProxy = addressFile.getContractAddress('KasuController');
    const kasuPoolExternalTVLProxy = addressFile.getContractAddress('KasuPoolExternalTVL');

    console.log();
    console.log('========================================');
    console.log('XDC USDC RECOVERY: finish init');
    console.log('========================================');
    console.log();
    console.log('Network:', chainConfig.name, `(${networkName})`);
    console.log('Deployer:', deployerAddress);
    console.log();
    console.log('SystemVariables proxy:      ', systemVariablesProxy);
    console.log('KsuPrice proxy:             ', ksuPriceProxy);
    console.log('KasuController proxy:       ', kasuControllerProxy);
    console.log('KasuPoolExternalTVL proxy:  ', kasuPoolExternalTVLProxy);
    console.log();
    console.log('Aligned epoch start (ts):   ', alignedEpochStart);
    console.log('Aligned epoch start (UTC):  ', new Date(alignedEpochStart * 1000).toUTCString());
    console.log();

    // Prepare setup struct
    const isLiteDeployment = chainConfig.deploymentMode === 'lite';
    const setup: SystemVariablesSetupStruct = {
        initialEpochStartTimestamp: alignedEpochStart,
        clearingPeriodLength: 3600 * 48,
        performanceFee: 10_00,
        loyaltyThresholds: isLiteDeployment ? [] : [1_00, 5_00],
        defaultTrancheInterestChangeEpochDelay: 4,
        ecosystemFeeRate: 0,
        protocolFeeRate: 100_00,
        protocolFeeReceiver: chainConfig.protocolFeeReceiver,
    };

    // ---- Step 1: Record current SV impl ----
    const originalImplAddress = await upgrades.erc1967.getImplementationAddress(
        systemVariablesProxy,
    );
    console.log('Current SV impl (production):', originalImplAddress);
    console.log();

    // ---- Step 2: Upgrade SV proxy to SystemVariablesMigration + initialize atomically ----
    console.log('>> Upgrading SV proxy to SystemVariablesMigration (with initialize call)...');
    const MigrationFactory = await ethers.getContractFactory(
        'SystemVariablesMigration',
        deployerSigner,
    );
    const upgradedProxy = await upgrades.upgradeProxy(
        systemVariablesProxy,
        MigrationFactory,
        {
            ...deployOptions(deployerAddress, [ksuPriceProxy, kasuControllerProxy]),
            call: { fn: 'initialize', args: [setup] },
        },
    );
    await upgradedProxy.waitForDeployment();
    const migrationImplAddress = await upgrades.erc1967.getImplementationAddress(
        systemVariablesProxy,
    );
    console.log('   Migration impl address:   ', migrationImplAddress);
    console.log('   Upgrade + initialize: OK');
    console.log();

    // ---- Step 3: Verify state ----
    const sv = SystemVariables__factory.connect(systemVariablesProxy, deployerSigner);
    const writtenEpoch0 = await sv.epochStartTimestamp(0);
    const currentEpoch = await sv.currentEpochNumber();
    console.log('   epochStartTimestamp(0):', writtenEpoch0.toString(), '(expected:', alignedEpochStart, ')');
    console.log('   currentEpochNumber:    ', currentEpoch.toString());
    if (Number(writtenEpoch0) !== alignedEpochStart) {
        throw new Error(
            `State mismatch: epochStartTimestamp(0)=${writtenEpoch0} expected=${alignedEpochStart}`,
        );
    }
    console.log('   State verified OK');
    console.log();

    // ---- Step 4: Upgrade SV proxy BACK to production SystemVariables impl ----
    console.log('>> Upgrading SV proxy BACK to production SystemVariables impl...');
    const ProductionFactory = await ethers.getContractFactory(
        'SystemVariables',
        deployerSigner,
    );
    const revertedProxy = await upgrades.upgradeProxy(
        systemVariablesProxy,
        ProductionFactory,
        deployOptions(deployerAddress, [ksuPriceProxy, kasuControllerProxy]),
    );
    await revertedProxy.waitForDeployment();
    const finalImplAddress = await upgrades.erc1967.getImplementationAddress(
        systemVariablesProxy,
    );
    console.log('   Final SV impl address:    ', finalImplAddress);
    console.log();

    // Re-verify state is preserved after the rollback
    const finalEpoch0 = await sv.epochStartTimestamp(0);
    const finalCurrentEpoch = await sv.currentEpochNumber();
    console.log('   epochStartTimestamp(0) after rollback:', finalEpoch0.toString());
    console.log('   currentEpochNumber after rollback:    ', finalCurrentEpoch.toString());
    if (Number(finalEpoch0) !== alignedEpochStart) {
        throw new Error(
            `Post-rollback state mismatch: epochStartTimestamp(0)=${finalEpoch0} expected=${alignedEpochStart}`,
        );
    }
    console.log('   Rollback state preserved OK');
    console.log();

    // ---- Step 5: Initialize KasuPoolExternalTVL (was pending from failed deploy_1) ----
    console.log('>> Initializing KasuPoolExternalTVL...');
    const kasuPoolExternalTVL = KasuPoolExternalTVL__factory.connect(
        kasuPoolExternalTVLProxy,
        adminSigner,
    );
    const externalTVLBaseURI = process.env.EXTERNAL_TVL_BASE_URI ?? '';
    const tx = await kasuPoolExternalTVL.initialize(externalTVLBaseURI);
    await tx.wait(1);
    console.log('   KasuPoolExternalTVL initialized');
    console.log();

    console.log('========================================');
    console.log('XDC USDC RECOVERY COMPLETE');
    console.log('========================================');
    console.log();
    console.log('Next step: npx hardhat --network xdc-usdc run scripts/deploy_2.ts');
    console.log();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
