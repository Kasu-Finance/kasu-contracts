import { MockUSDC__factory } from '../../typechain-types';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';

export async function mockUsdcMintUser(
    usersMint: { user: Signer; amount: bigint }[],
    adminAccount: Signer,
) {
    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    console.info('Funding accounts with USDC');

    const usdcAdmin = MockUSDC__factory.connect(
        deploymentAddresses['USDC'].address,
        adminAccount,
    );

    const usersMintMap = new Map<string, bigint>();
    for (const userMint of usersMint.values()) {
        const userAddress = await userMint.user.getAddress();
        const previousAmount = usersMintMap.get(userAddress) ?? 0n;
        usersMintMap.set(userAddress, previousAmount + userMint.amount);
    }

    let tx: ContractTransactionResponse;
    for (const userMint of usersMintMap.entries()) {
        tx = await usdcAdmin.mint(userMint[0], userMint[1]);
        await tx.wait(1);
    }
}
