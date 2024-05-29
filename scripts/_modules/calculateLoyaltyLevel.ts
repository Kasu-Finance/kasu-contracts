import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { UserManager__factory } from '../../typechain-types';
import { ContractTransactionResponse, Signer } from 'ethers';

export async function calculateLoyaltyLevel(
    batchSize = 1000,
    userAccount: Signer,
) {
    const addressFile = deploymentFileFactory(hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    const userManager = UserManager__factory.connect(
        deploymentAddresses.UserManager.address,
        userAccount,
    );

    console.log('Calculate user loyalty levels batch', batchSize);
    let tx: ContractTransactionResponse;
    tx = await userManager.batchCalculateUserLoyaltyLevels(batchSize);
    await tx.wait(1);
}
