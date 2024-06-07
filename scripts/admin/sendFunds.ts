import { ERC20__factory } from '../../typechain-types';
import * as hre from 'hardhat';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import { ContractTransactionResponse } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';

const recipients = [
    '0x022d1b8c2808702013bb52D0429F45FDC571dD53',
    '0xDFd2128009cB2eaeA93F637aAec22566d3F93Db7',
];

const ETH_TO_SEND = '0.02';
const USDC_TO_SEND = '25';
const KSU_TO_SEND = 'DO_NOT_SEND_KSU';

let USDC_ADDRESS = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';

async function main() {
    if (USDC_ADDRESS === '') {
        const addressFile = deploymentFileFactory(hre.network.name, 0);
        const deploymentAddresses = addressFile.getContractAddresses();
        USDC_ADDRESS = deploymentAddresses.USDC.address;
    }

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];

    // contracts
    const usdcContract = ERC20__factory.connect(USDC_ADDRESS, admin);

    let tx: ContractTransactionResponse;

    for (const recipient of recipients) {
        console.log(`Sending ${ETH_TO_SEND} ETH to ${recipient}`);
        let tx = await admin.sendTransaction({
            to: recipient,
            value: hre.ethers.parseEther(ETH_TO_SEND),
        });
        await tx.wait();
        console.log(`Sending ${USDC_TO_SEND} USDC to ${recipient}`);
        tx = await usdcContract.transfer(
            recipient,
            hre.ethers.parseUnits(USDC_TO_SEND, 6),
        );
        await tx.wait();
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
