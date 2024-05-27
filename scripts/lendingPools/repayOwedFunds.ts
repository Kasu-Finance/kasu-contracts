import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { getLogFilePath } from '../_utils/addressFileFactory';
import fs from 'fs';
import {
    LendingPoolManager__factory,
    MockUSDC__factory,
} from '../../typechain-types';
import { parseKasuError } from '../_utils/parseErrors';

const lendingPoolAddress = '0x2F9c56edD3Ba0a06AA58767f50E52761D85f3Bc7';
const repayAmount = '1001825000';

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
    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        admin,
    );

    const mockUSDCAdmin = MockUSDC__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    // interactions
    await mockUSDCAdmin.approve(
        deploymentAddresses.LendingPoolManager.address,
        repayAmount,
    );

    const adminAddress = await admin.getAddress();

    try {
        await lendingPoolManager.repayOwedFunds(
            lendingPoolAddress,
            repayAmount,
            adminAddress,
        );
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
