import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { getLogFilePath } from '../_utils/addressFileFactory';
import fs from 'fs';
import { LendingPoolManager__factory } from '../../typechain-types';
import { parseKasuError } from '../_utils/parseErrors';
import { ContractTransactionResponse } from 'ethers';

const lendingPoolAddress = '0xb93c239690061228110525aa16622345241b388e';

async function main() {
    // file
    const { filePath } = getLogFilePath(hre.network.name);
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

    let tx: ContractTransactionResponse;
    // interactions
    try {
        console.log('stopLendingPool...');
        tx = await lendingPoolManagerAdmin.stopLendingPool(lendingPoolAddress);
        await tx.wait();
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
