import { Signer } from 'ethers';
import * as hre from 'hardhat';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import fs from 'fs';
import {
    ERC20__factory,
    LendingPool__factory,
    LendingPoolManager__factory,
} from '../../typechain-types';
import { mockUsdcMintUser } from './mockUsdcMintUsers';

export async function repayPool(
    lendingPoolAddress: string,
    fundsManagerAccount: Signer,
    repayAmount: bigint,
    doRepayFees = false,
) {
    const { filePath } = getDeploymentFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // contracts
    const lendingPoolManager = LendingPoolManager__factory.connect(
        deploymentAddresses.LendingPoolManager.address,
        fundsManagerAccount,
    );

    const usdc = ERC20__factory.connect(
        deploymentAddresses['USDC'].address,
        fundsManagerAccount,
    );

    console.log(
        `repaying funds to pool`,
        lendingPoolAddress,
        `repay amount in USDC `,
        repayAmount,
        "doRepayFees",
        doRepayFees,
    );

    if (doRepayFees) {
        const feesAmount = await LendingPool__factory.connect(lendingPoolAddress, fundsManagerAccount).feesOwedAmount();

        repayAmount += feesAmount;

        console.log("repay fees amount", feesAmount);
    }

    await mockUsdcMintUser(
        [{
            user: fundsManagerAccount,
            amount: repayAmount,
        }],
        fundsManagerAccount,
    )

    let tx;

    tx = await usdc.approve(await lendingPoolManager.getAddress(), repayAmount);
    await tx.wait(1);

    tx = await lendingPoolManager.repayOwedFunds(
        lendingPoolAddress,
        repayAmount,
        await fundsManagerAccount.getAddress()
    );
    await tx.wait(1);
}
