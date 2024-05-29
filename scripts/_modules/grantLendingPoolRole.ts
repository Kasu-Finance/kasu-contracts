import { KasuController__factory } from '../../typechain-types';
import { ContractTransactionResponse, Signer, Wallet } from 'ethers';
import hre from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { getAccounts } from './getAccounts';

export const ROLE_POOL_CLEARING_MANAGER = hre.ethers.id(
    'ROLE_POOL_CLEARING_MANAGER',
);
export const ROLE_POOL_FUNDS_MANAGER = hre.ethers.id('ROLE_POOL_FUNDS_MANAGER');
export const ROLE_POOL_MANAGER = hre.ethers.id('ROLE_POOL_MANAGER');

export async function grantLendingPoolRole(
    lendingPool: string,
    accountAddress: string,
    role: string,
) {
    let tx: ContractTransactionResponse;

    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

    // signers
    const namedSigners = await getAccounts(hre.network.name);
    const adminAccount = namedSigners[0];

    // access control
    const kasuControllerAdmin = KasuController__factory.connect(
        addressFile.getContractAddress('KasuController'),
        adminAccount,
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
