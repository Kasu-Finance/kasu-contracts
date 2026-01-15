import { ERC20__factory, MockUSDC__factory } from '../../typechain-types';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import * as hre from 'hardhat';
import { ContractTransactionResponse, Signer } from 'ethers';

const LOCAL_NETWORKS = new Set(['localhost', 'hardhat']);

function resolveIsMockUsdc(): boolean {
    const envValue = process.env.USDC_IS_MOCK;
    if (envValue && envValue.length > 0) {
        return envValue.toLowerCase() === 'true';
    }

    return LOCAL_NETWORKS.has(hre.network.name);
}

export function isMockUsdc(): boolean {
    return resolveIsMockUsdc();
}

export function getUsdcContract(addresses: Record<string, { address: string }>, signer: Signer) {
    return ERC20__factory.connect(addresses.USDC.address, signer);
}

export async function fundUsdcUsers(
    usersMint: { user: Signer; amount: bigint }[],
    adminAccount: Signer,
    allowSkip = false,
) {
    if (!isMockUsdc()) {
        if (allowSkip) {
            console.warn('USDC_IS_MOCK is false; skipping mint.');
            return;
        }
        throw new Error(
            'USDC_IS_MOCK is false; refusing to mint on non-mock USDC.',
        );
    }

    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    console.info('Funding accounts with USDC');

    const usdcAdmin = MockUSDC__factory.connect(
        deploymentAddresses.USDC.address,
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
