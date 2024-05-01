import path from 'path';
import fs from 'fs';
// import * as deploymentAddresses from '../deployments/base-testnet/addresses-base-testnet.json';
import { ERC20__factory } from '../typechain-types';
import * as hre from 'hardhat';

const recipients = ['0x97cbcD33f1075070e59F354E4eCf71Ed6267E1ED'];

async function main() {
    const deploymentAddressesPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(deploymentAddressesPath).toString(),
    );

    // signers
    const signers = await hre.ethers.getSigners();
    const admin = signers[0];
    // contracts
    const ksuContract = ERC20__factory.connect(
        deploymentAddresses.KSU.address,
        admin,
    );
    const usdcContract = ERC20__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );

    for (const recipient of recipients) {
        console.log(`Sending 0.1 ETH and 10000 KSU to ${recipient}`);
        let tx = await admin.sendTransaction({
            to: recipient,
            value: hre.ethers.parseEther('0.1'),
        });
        await tx.wait();
        tx = await ksuContract.transfer(
            recipient,
            hre.ethers.parseEther('10000'),
        );
        await tx.wait();
        tx = await usdcContract.transfer(
            recipient,
            hre.ethers.parseUnits('100000', 6),
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
