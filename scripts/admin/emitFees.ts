import { ERC20__factory, KSULocking__factory } from '../../typechain-types';
import * as hre from 'hardhat';
import { addressFileFactory } from '../_utils/_logs';
import { getAccounts } from '../_utils/getAccounts';

async function main() {
    const addressFile = addressFileFactory(0, hre.network.name);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[0];
    // contracts
    const usdcContract = ERC20__factory.connect(
        deploymentAddresses.USDC.address,
        admin,
    );
    const ksuLockingContract = KSULocking__factory.connect(
        deploymentAddresses.KSULocking.address,
        admin,
    );

    const feesAmount = hre.ethers.parseUnits('10000', 6);
    let tx = await usdcContract.approve(
        await ksuLockingContract.getAddress(),
        feesAmount,
    );
    await tx.wait();

    tx = await ksuLockingContract.emitFees(feesAmount);
    await tx.wait();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
