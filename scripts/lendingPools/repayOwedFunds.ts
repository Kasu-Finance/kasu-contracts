import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    ERC20__factory,
} from '../../typechain-types';
import { parseKasuError } from '../_utils/parseErrors';
import { ContractTransactionResponse } from 'ethers';
import { requireEnv, requireEnvBigInt } from '../_utils/env';

// Required environment variables:
// LENDING_POOL_ADDRESS - address of the lending pool
// REPAY_AMOUNT - amount to repay in raw units (e.g., 100000000 for 100 USDC)
const lendingPoolAddress = requireEnv('LENDING_POOL_ADDRESS');
const repayAmount = requireEnvBigInt('REPAY_AMOUNT');

async function main() {
    // file
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[0];

    // contracts
    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        admin,
    );

    const usdcAdmin = ERC20__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    let tx: ContractTransactionResponse;

    // interactions
    console.log('Approving amount...');
    tx = await usdcAdmin.approve(
        deploymentAddresses.LendingPoolManager.address,
        repayAmount,
    );
    await tx.wait();

    const adminAddress = await admin.getAddress();

    try {
        console.log('repayOwedFunds...');
        tx = await lendingPoolManagerAdmin.repayOwedFunds(
            lendingPoolAddress,
            repayAmount,
            adminAddress,
        );
        await tx.wait();
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
