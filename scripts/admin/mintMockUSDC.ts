import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { MockUSDC__factory } from '../../typechain-types';
import { getAccounts } from '../_modules/getAccounts';

const recipients = ['0x68ea8544AA64479c592711205B59F92122E0893c'];

const USDC_TO_MINT = '100000';

async function main() {
    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];

    // contracts
    const mockUsdcContract = MockUSDC__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    // mint
    for (const recipient of recipients) {
        console.log(`Sending ${USDC_TO_MINT} USDC to ${recipient}`);
        await mockUsdcContract.mint(
            recipient,
            hre.ethers.parseUnits(USDC_TO_MINT, 6),
        );
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
