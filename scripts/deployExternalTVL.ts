import hre from 'hardhat';
import { ContractTransactionResponse } from 'ethers';
import { KasuPoolExternalTVL__factory } from '../typechain-types/factories/src/token/KasuPoolExternalTVL__factory';
import { deploymentFileFactory } from './_utils/deploymentFileFactory';
import { deployFactory, deployOptions } from './_utils/deployFactory';
import { getAccounts } from './_modules/getAccounts';

// Config
const deployUpdates = false;
const verifySource = true;

// Optional: set via env EXTERNAL_TVL_BASE_URI, defaults to empty string
const DEFAULT_BASE_URI = process.env.EXTERNAL_TVL_BASE_URI ?? '';

async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

    const isNewDeployment = !addressFile.didFileInitiallyExist;
    console.log(`Is new deployment: ${isNewDeployment}`);

    // get signers
    const signers = await getAccounts(hre.network.name);
    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();
    const adminSigner = signers[1] ?? deployerSigner;

    console.log();
    console.log('deployer account: ', deployerAddress);
    console.log('admin account: ', await adminSigner.getAddress());
    console.log();

    const { deployTransparentProxy } = await deployFactory(
        addressFile,
        isNewDeployment,
        deployUpdates,
        verifySource,
        deployerSigner,
    );

    // Read KasuController from deployment file
    const kasuControllerAddress = addressFile.getContractAddress('KasuController');

    // Deploy proxy for KasuPoolDepositToken (External TVL)
    const kasuPoolExternalTVLAddress = await deployTransparentProxy(
        'KasuPoolExternalTVL',
        deployOptions(deployerAddress, [kasuControllerAddress]),
        'KasuPoolExternalTVL',
    );

    console.log('KasuPoolExternalTVL proxy deployed at: ', kasuPoolExternalTVLAddress);

    // Initialize with base URI
    const token = KasuPoolExternalTVL__factory.connect(
        kasuPoolExternalTVLAddress,
        adminSigner,
    );

    let tx: ContractTransactionResponse;
    tx = await token.initialize(DEFAULT_BASE_URI);
    await tx.wait(1);
    console.log('KasuPoolExternalTVL initialized.');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});


