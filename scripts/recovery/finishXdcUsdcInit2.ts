/**
 * Continuation of finishXdcUsdcInit.ts.
 *
 * Step 1 + 2 already completed successfully:
 *  - SV proxy upgraded to SystemVariablesMigration
 *  - initialize(setup) ran with aligned epoch start 1717653600 (via 1718258400 anchor +... wait no, see below)
 *
 * Actual on-chain state verified:
 *  - epochStartTimestamp(0) = 1718258400 (Thu 13 Jun 2024 06:00 UTC)
 *  - currentEpochNumber = 95
 *  - _initialized = 1
 *  - SV impl = 0x57005c3e34fc372543c4c67741073c1f3dd0c4c1 (migration impl)
 *
 * Remaining steps:
 *  3. Upgrade SV proxy BACK to production SystemVariables impl
 *  4. Initialize KasuPoolExternalTVL
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

async function main() {
    const networkName = hre.network.name;
    if (networkName !== 'xdc-usdc') {
        throw new Error(`Only for xdc-usdc. Got: ${networkName}`);
    }

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(networkName, blockNumber);
    const chainConfig = getChainConfig(networkName);
    const signers = await getAccounts(networkName);
    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();
    const adminSigner = signers[1];

    const systemVariablesProxy = addressFile.getContractAddress('SystemVariables');
    const ksuPriceProxy = addressFile.getContractAddress('KsuPrice');
    const kasuControllerProxy = addressFile.getContractAddress('KasuController');
    const kasuPoolExternalTVLProxy = addressFile.getContractAddress('KasuPoolExternalTVL');

    console.log();
    console.log('========================================');
    console.log('XDC USDC RECOVERY (continuation)');
    console.log('========================================');
    console.log();

    // ---- Pre-check: read state via raw storage to avoid stale RPC cache ----
    const implSlot = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';
    const implRaw = await hre.ethers.provider.getStorage(systemVariablesProxy, implSlot);
    const currentImpl = '0x' + implRaw.slice(-40);
    console.log('Current SV impl (raw storage):', currentImpl);

    const sv = SystemVariables__factory.connect(systemVariablesProxy, deployerSigner);
    const e0 = await sv.epochStartTimestamp(0);
    const ec = await sv.currentEpochNumber();
    console.log('epochStartTimestamp(0):', e0.toString());
    console.log('currentEpochNumber:    ', ec.toString());
    if (e0 !== 1718258400n) {
        throw new Error(`Unexpected state: epochStartTimestamp(0)=${e0}, expected 1718258400`);
    }
    console.log('   State OK (epoch aligned to XDC AUDD)');
    console.log();

    // ---- Step 3: Rollback SV proxy to production SystemVariables impl ----
    console.log('>> Rolling back SV proxy to production SystemVariables impl...');
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

    // Re-read impl address from raw storage
    const implRaw2 = await hre.ethers.provider.getStorage(systemVariablesProxy, implSlot);
    const finalImpl = '0x' + implRaw2.slice(-40);
    console.log('   Final SV impl (raw storage):', finalImpl);

    // Re-verify state preserved
    const e0After = await sv.epochStartTimestamp(0);
    const ecAfter = await sv.currentEpochNumber();
    console.log('   epochStartTimestamp(0) after rollback:', e0After.toString());
    console.log('   currentEpochNumber after rollback:    ', ecAfter.toString());
    if (e0After !== 1718258400n) {
        throw new Error(
            `Post-rollback state mismatch: epochStartTimestamp(0)=${e0After} expected=1718258400`,
        );
    }
    console.log('   Rollback OK');
    console.log();

    // ---- Step 4: Initialize KasuPoolExternalTVL ----
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

    // ---- Update addresses file with final impl ----
    addressFile.writeAddressProxy(
        'SystemVariables',
        systemVariablesProxy,
        finalImpl,
        'TransparentProxy',
    );

    console.log('========================================');
    console.log('RECOVERY COMPLETE');
    console.log('========================================');
    console.log();
    console.log('Next: npx hardhat --network xdc-usdc run scripts/deploy_2.ts');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
