import { Signer } from 'ethers';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import {
    LendingPoolManager__factory,
} from '../../typechain-types';
import { mockUsdcMintUser } from './mockUsdcMintUsers';

export async function repayPool(
    lendingPoolAddress: string,
    fundsManagerAccount: Signer,
    repayAmount: bigint,
) {
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    await mockUsdcMintUser(
        [{
            user: fundsManagerAccount,
            amount: repayAmount,
        }],
        fundsManagerAccount,
    )

    // contracts
    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        fundsManagerAccount,
    );

    let tx;

    console.log(
        `repaying funds to pool`,
        lendingPoolAddress,
        `repay amount in USDC `,
        repayAmount,
    );
    tx = await lendingPoolManager.repayOwedFunds(
        lendingPoolAddress,
        repayAmount,
        await fundsManagerAccount.getAddress()
    );
    await tx.wait(1);
}
