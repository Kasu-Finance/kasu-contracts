import { deployFactory, deployOptions } from './_utils/deployFactory';
import hre from 'hardhat';
import { addressFileFactory } from './_utils/addressFileFactory';
import { getAccounts } from './_modules/getAccounts';

async function main() {
    // setup
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = addressFileFactory(blockNumber, hre.network.name);

    const isNewDeployment = !addressFile.didFileInitiallyExist;
    console.log(`Is new deployment: ${isNewDeployment}`);

    const { deployTransparentProxy, deployBeacon } = await deployFactory(
        addressFile,
        isNewDeployment,
    );

    const signers = await getAccounts(hre.network.name);

    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();

    // contract addresses
    const mockKsuPriceDeploymentAddress =
        addressFile.getContractAddress('KsuPrice');

    const kasuControllerDeploymentAddress =
        addressFile.getContractAddress('KasuController');

    // upgrade

    await deployTransparentProxy(
        'SystemVariables',
        deployOptions(deployerAddress, [
            mockKsuPriceDeploymentAddress,
            kasuControllerDeploymentAddress,
        ]),
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
