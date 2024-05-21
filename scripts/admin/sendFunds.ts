import { ERC20__factory } from '../../typechain-types';
import * as hre from 'hardhat';
import { addressFileFactory } from '../_utils/addressFileFactory';
import { ContractTransactionResponse } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';

const recipients = [
    '0x022d1b8c2808702013bb52D0429F45FDC571dD53',
    '0xDFd2128009cB2eaeA93F637aAec22566d3F93Db7',
];

const ETH_TO_SEND = '0.025';
const KSU_TO_SEND = '10000';
const USDC_TO_SEND = '10000';

async function main() {
    const addressFile = addressFileFactory(0, hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];
    // contracts
    const ksuContract = ERC20__factory.connect(
        deploymentAddresses.KSU.address,
        admin,
    );
    const usdcContract = ERC20__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    let tx: ContractTransactionResponse;

    for (const recipient of recipients) {
        console.log(`Sending ${ETH_TO_SEND} ETH to ${recipient}`);
        let tx = await admin.sendTransaction({
            to: recipient,
            value: hre.ethers.parseEther(ETH_TO_SEND),
        });
        await tx.wait();
        console.log(`Sending ${KSU_TO_SEND} KSU to ${recipient}`);
        tx = await ksuContract.transfer(
            recipient,
            hre.ethers.parseEther('10000'),
        );
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
