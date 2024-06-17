import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    MockUSDC__factory,
} from '../../typechain-types';
import { parseKasuError } from '../_utils/parseErrors';
import { ContractTransactionResponse } from 'ethers';

const lendingPoolAddress = '0xb93c239690061228110525aa16622345241b388e';
const repayAmount = 100_000_000;

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

    const mockUSDCAdmin = MockUSDC__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    let tx: ContractTransactionResponse;

    // interactions
    console.log('Approving amount...');
    tx = await mockUSDCAdmin.approve(
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
