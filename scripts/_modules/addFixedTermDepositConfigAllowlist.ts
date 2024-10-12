import {
    LendingPoolManager__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';

export async function addFixedTermDepositConfigAllowlist(
    lendingPool: string,
    configId: bigint,
    users: string[],
    isAllowedList: boolean[],
    adminAccount: Signer
) {
    let tx: ContractTransactionResponse;

    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers

    console.info('admin account address', await adminAccount.getAddress());

    // create lending pool
    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses['LendingPoolManager'].address,
        adminAccount,
    );

    tx = await lendingPoolManagerAdmin.updateFixedTermDepositAllowlist(
        lendingPool,
        configId,
        users,
        isAllowedList
    );
    await tx.wait(1);
}
