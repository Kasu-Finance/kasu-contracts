import { SystemVariablesTestable__factory } from '../../typechain-types';
import { ContractTransactionResponse, Signer } from 'ethers';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';

export async function starClearing(adminAccount: Signer) {
    const deploymentFile = deploymentFileFactory(hre.network.name);
    const deploymentAddresses = deploymentFile.getContractAddresses();

    const systemVariablesTestableAdmin =
        SystemVariablesTestable__factory.connect(
            deploymentAddresses.SystemVariables.address,
            adminAccount,
        );
    let tx: ContractTransactionResponse;
    tx = await systemVariablesTestableAdmin.startClearing();
    await tx.wait(1);
}

export async function endClearing(adminAccount: Signer) {
    const deploymentFile = deploymentFileFactory(hre.network.name);
    const deploymentAddresses = deploymentFile.getContractAddresses();

    const systemVariablesTestableAdmin =
        SystemVariablesTestable__factory.connect(
            deploymentAddresses.SystemVariables.address,
            adminAccount,
        );
    let tx: ContractTransactionResponse;
    tx = await systemVariablesTestableAdmin.endClearing();
    await tx.wait(1);
}
