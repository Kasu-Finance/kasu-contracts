import { deployFactory, deployOptions } from './_utils/deployFactory';
import hre from 'hardhat';
import { deploymentFileFactory } from './_utils/deploymentFileFactory';
import { getAccounts } from './_modules/getAccounts';

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

    const lendingPoolManagerDeploymentAddress =
        addressFile.getContractAddress('LendingPoolManager');

    const clearingCoordinatorDeploymentAddress = addressFile.getContractAddress(
        'ClearingCoordinator',
    );

    const feeManagerDeploymentAddress =
        addressFile.getContractAddress('FeeManager');

    const mockUsdcDeploymentAddress = addressFile.getContractAddress('USDC');

    // upgrade
    const lendingPoolBeaconAddress = await deployBeacon(
        'LendingPool',
        deployOptions(deployerAddress, [
            systemVariablesDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
            clearingCoordinatorDeploymentAddress,
            feeManagerDeploymentAddress,
            mockUsdcDeploymentAddress,
        ]),
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
