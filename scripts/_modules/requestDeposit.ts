import { ContractTransactionResponse, Signer } from 'ethers';
import {
    KasuAllowList__factory,
    LendingPoolManager__factory,
    MockUSDC__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import fs from 'fs';
import { addressFileFactory, getLogFilePath } from '../_utils/_logs';
import { getAccounts } from './getAccounts';

export type RequestDepositInput = {
    user: Signer;
    lendingPoolAddress: string;
    trancheAddress: string;
    amount: bigint;
};

export async function requestDeposits(
    requestDepositsInput: RequestDepositInput[],
) {
    let tx: ContractTransactionResponse;

    const addressFile = addressFileFactory(0, hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[0];

    // fund accounts
    console.info('Funding accounts with USDC');

    const usdcAdmin = MockUSDC__factory.connect(
        deploymentAddresses['USDC'].address,
        adminAccount,
    );

    for (const rdi of requestDepositsInput) {
        const userAddress = await rdi.user.getAddress();
        tx = await usdcAdmin.mint(userAddress, rdi.amount);
        await tx.wait(1);
    }

    // add users to allow list
    console.info('Add users to allow list');
    const kasuAllowListAdmin = KasuAllowList__factory.connect(
        deploymentAddresses['KasuAllowList'].address,
        adminAccount,
    );

    const userAddresses: string[] = [];
    for (const rdi of requestDepositsInput) {
        userAddresses.push(await rdi.user.getAddress());
    }

    const uniqueUserAddresses = [...new Set(userAddresses)];
    for (const uniqueUserAddress of uniqueUserAddresses) {
        tx = await kasuAllowListAdmin.allowUser(uniqueUserAddress);
        await tx.wait(1);
    }

    // request deposits
    for (const rd of requestDepositsInput) {
        await requestDeposit(
            deploymentAddresses,
            rd.user,
            rd.lendingPoolAddress,
            rd.trancheAddress,
            rd.amount,
        );
    }
}

async function requestDeposit(
    addresses: any,
    requester: Signer,
    lendingPoolAddress: string,
    trancheAddress: string,
    amount: bigint,
) {
    let tx: ContractTransactionResponse;

    console.info('User deposit request');
    const usdcRequester = MockUSDC__factory.connect(
        addresses['USDC'].address,
        requester,
    );

    tx = await usdcRequester.approve(
        addresses['LendingPoolManager'].address,
        amount,
    );
    await tx.wait(1);

    const lendingPoolManagerAlice = LendingPoolManager__factory.connect(
        addresses['LendingPoolManager'].address,
        requester,
    );
    tx = await lendingPoolManagerAlice.requestDeposit(
        lendingPoolAddress,
        trancheAddress,
        amount,
        '0x',
    );
    await tx.wait(1);
    return tx;
}
