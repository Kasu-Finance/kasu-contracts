import hre, { ethers, upgrades } from 'hardhat';
import { getDeploymentFilePath } from './_utils/deploymentFileFactory';
import { getAccounts } from './_modules/getAccounts';
import { parseKasuError } from './_utils/parseErrors';
import { SystemVariables__factory } from '../typechain-types';
import fs from 'fs';
import { ContractTransactionResponse } from 'ethers';

async function main() {
    // setup
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];

    // contracts
    const systemVariablesImplementation = await ethers.getContractFactory(
        'SystemVariables',
    );

    const systemVariables = SystemVariables__factory.connect(
        deploymentAddresses.SystemVariables.address,
        adminAccount,
    );

    let tx: ContractTransactionResponse;

    try {
        const currentEpochNumber = await systemVariables.currentEpochNumber();
        console.log(currentEpochNumber);
    } catch (error) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
