import {
    LendingPoolManager__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';

type FixedTermDepositConfig = {
    tranche: string,
    epochLockDuration: number,
    epochInterestRate: number,
    whitelistedOnly: boolean
}

export async function addFixedTermDeposit(
    lendingPool: string,
    fixedTermDepositConfig: FixedTermDepositConfig,
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

    const configId = await lendingPoolManagerAdmin.addLendingPoolTrancheFixedTermDeposit.staticCall(
        lendingPool,
        fixedTermDepositConfig.tranche,
        fixedTermDepositConfig.epochLockDuration,
        fixedTermDepositConfig.epochInterestRate,
        fixedTermDepositConfig.whitelistedOnly
    );

    tx = await lendingPoolManagerAdmin.addLendingPoolTrancheFixedTermDeposit(
        lendingPool,
        fixedTermDepositConfig.tranche,
        fixedTermDepositConfig.epochLockDuration,
        fixedTermDepositConfig.epochInterestRate,
        fixedTermDepositConfig.whitelistedOnly
    );
    await tx.wait(1);

    return configId;
}
