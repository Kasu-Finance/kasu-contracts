import { ContractTransactionResponse, Signer } from 'ethers';
import {
    KasuAllowList__factory,
    LendingPoolManager__factory,
    MockUSDC__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import fs from 'fs';
import {
    deploymentFileFactory,
    getDeploymentFilePath,
} from '../_utils/deploymentFileFactory';
import { getAccounts } from './getAccounts';
import { allowUsers } from './allowUsers';
import { mockUsdcMintUser } from './mockUsdcMintUsers';

export type RequestDepositInput = {
    user: Signer;
    lendingPoolAddress: string;
    trancheAddress: string;
    amount: bigint;
};

export async function requestDeposits(
    requestDepositsInput: RequestDepositInput[],
    fundAccounts = true,
    allowAccounts = true,
) {
    let tx: ContractTransactionResponse;

    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];

    // fund accounts
    if (fundAccounts) {
        await mockUsdcMintUser(
            requestDepositsInput.map((it) => {
                return { user: it.user, amount: it.amount };
            }),
            adminAccount,
        );
    }

    // allow accounts
    if (allowAccounts) {
        await allowUsers(
            requestDepositsInput.map((it) => it.user),
            adminAccount,
        );
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

    const lendingPoolManagerUser = LendingPoolManager__factory.connect(
        addresses['LendingPoolManager'].address,
        requester,
    );
    tx = await lendingPoolManagerUser.requestDeposit(
        lendingPoolAddress,
        trancheAddress,
        amount,
        '0x',
    );
    await tx.wait(1);
    return tx;
}
