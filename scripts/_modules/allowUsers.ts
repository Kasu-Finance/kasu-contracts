import { KasuAllowList__factory } from '../../typechain-types';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';

export async function allowUsers(users: Signer[], adminAccount: Signer) {
    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    console.info('Add users to allow list');
    const kasuAllowListAdmin = KasuAllowList__factory.connect(
        deploymentAddresses['KasuAllowList'].address,
        adminAccount,
    );

    const uniqueUserAddresses = new Set<string>();
    for (const user of users) {
        uniqueUserAddresses.add(await user.getAddress());
    }

    let tx: ContractTransactionResponse;
    for (const uniqueUserAddress of uniqueUserAddresses) {
        tx = await kasuAllowListAdmin.allowUser(uniqueUserAddress);
        await tx.wait(1);
    }
}
