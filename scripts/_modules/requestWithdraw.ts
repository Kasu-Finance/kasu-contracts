import { ContractTransactionResponse, Signer } from 'ethers';
import { LendingPoolManager__factory } from '../../typechain-types';
import path from 'path';
import * as hre from 'hardhat';
import fs from 'fs';
import { addressFileFactory } from '../_utils/addressFileFactory';

export type RequestWithdrawInput = {
    user: Signer;
    lendingPoolAddress: string;
    trancheAddress: string;
    shares: bigint;
};

export async function requestWithdrawals(
    requestDepositsInput: RequestWithdrawInput[],
) {
    const addressFile = addressFileFactory(0, hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    // request withdraw
    for (const rd of requestDepositsInput) {
        await requestWithdraw(
            deploymentAddresses,
            rd.user,
            rd.lendingPoolAddress,
            rd.trancheAddress,
            rd.shares,
        );
    }
}

async function requestWithdraw(
    addresses: any,
    requester: Signer,
    lendingPoolAddress: string,
    trancheAddress: string,
    amount: bigint,
) {
    let tx: ContractTransactionResponse;

    console.info('User withdraw request');

    const lendingPoolManagerAlice = LendingPoolManager__factory.connect(
        addresses['LendingPoolManager'].address,
        requester,
    );
    tx = await lendingPoolManagerAlice.requestWithdrawal(
        lendingPoolAddress,
        trancheAddress,
        amount,
    );
    await tx.wait(1);
    return tx;
}
