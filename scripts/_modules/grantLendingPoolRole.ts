import { KasuController__factory } from '../../typechain-types';
import { ContractTransactionResponse, Signer, Wallet } from 'ethers';
import hre from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getAccounts } from './getAccounts';

export const ROLE_POOL_ADMIN = hre.ethers.id('ROLE_POOL_ADMIN');
export const ROLE_POOL_MANAGER = hre.ethers.id('ROLE_POOL_MANAGER');
export const ROLE_POOL_CLEARING_MANAGER = hre.ethers.id(
    'ROLE_POOL_CLEARING_MANAGER',
);
export const ROLE_POOL_FUNDS_MANAGER = hre.ethers.id('ROLE_POOL_FUNDS_MANAGER');
export const ROLE_PROTOCOL_FEE_CLAIMER = hre.ethers.id(
    'ROLE_PROTOCOL_FEE_CLAIMER',
);

export async function grantLendingPoolRole(
    lendingPool: string,
    accountAddress: string,
    role: string,
    poolAdminAccount: Signer,
) {
    let tx: ContractTransactionResponse;

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

    // access control
    const kasuControllerAdmin = KasuController__factory.connect(
        addressFile.getContractAddress('KasuController'),
        poolAdminAccount,
    );

    console.info(
        `Granting role ${ROLE_POOL_CLEARING_MANAGER} to ${accountAddress}`,
    );
    tx = await kasuControllerAdmin.grantLendingPoolRole(
        lendingPool,
        role,
        accountAddress,
    );

    await tx.wait(1);
}
