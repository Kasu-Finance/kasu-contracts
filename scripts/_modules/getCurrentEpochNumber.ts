import {
    KasuAllowList__factory,
    SystemVariables__factory,
} from '../../typechain-types';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';

export async function getCurrentEpochNumber(account: Signer): Promise<bigint> {
    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    const systemVariables = SystemVariables__factory.connect(
        deploymentAddresses.SystemVariables.address,
        account,
    );

    return await systemVariables.currentEpochNumber();
}
