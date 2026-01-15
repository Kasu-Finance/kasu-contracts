import { KasuController__factory } from '../../typechain-types';
import { ContractTransactionResponse, Signer } from 'ethers';
import hre from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';

export const ROLE_LENDING_POOL_CREATOR = hre.ethers.id(
    'ROLE_LENDING_POOL_CREATOR',
);

export async function grantRole(
    accountAddress: string,
    role: string,
    adminAccount: Signer,
) {
    const addressFile = deploymentFileFactory(hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    let tx: ContractTransactionResponse;

    console.info(`Granting ${role} role to ${accountAddress}`);
    const kasuControllerAdmin = KasuController__factory.connect(
        deploymentAddresses['KasuController'].address,
        adminAccount,
    );
    tx = await kasuControllerAdmin.grantRole(role, accountAddress);
    await tx.wait(1);
}
