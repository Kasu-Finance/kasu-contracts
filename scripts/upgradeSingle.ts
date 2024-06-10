import { deployFactory, deployOptions } from './_utils/deployFactory';
import hre, { ethers, upgrades } from 'hardhat';
import { deploymentFileFactory } from './_utils/deploymentFileFactory';
import { getAccounts } from './_modules/getAccounts';
import { parseKasuError } from './_utils/parseErrors';

async function main() {
    // setup
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

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
    const systemVariablesDeploymentAddress =
        addressFile.getContractAddress('SystemVariables');

    const ksuPriceDeploymentAddress =
        addressFile.getContractAddress('KsuPrice');

    const kasuControllerDeploymentAddress =
        addressFile.getContractAddress('KasuController');

    console.log(
        systemVariablesDeploymentAddress,
        ksuPriceDeploymentAddress,
        kasuControllerDeploymentAddress,
    );

    const systemVariablesImplementation = await ethers.getContractFactory(
        'SystemVariables',
    );

    try {
        const proxy = await upgrades.upgradeProxy(
            systemVariablesDeploymentAddress,
            systemVariablesImplementation,
            deployOptions(deployerAddress, [
                ksuPriceDeploymentAddress,
                kasuControllerDeploymentAddress,
            ]),
        );

        await proxy.waitForDeployment();
    } catch (error) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
