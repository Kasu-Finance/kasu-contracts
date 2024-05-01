import * as hre from 'hardhat';
import { createLendingPool } from './utils/createLendingPool';
import { RequestDepositInput, requestDeposits } from './utils/requestDeposit';
import { runClearing } from './utils/runClearing';
import {
    requestWithdrawals,
    RequestWithdrawInput,
} from './utils/requestWithdraw';

const clearing1DrawAmount = hre.ethers.parseUnits('2500', 6); // 2500 USDC
const clearing2DrawAmount = hre.ethers.parseUnits('1000', 6); // 1000 USDC

async function main() {
    // create lending pool
    const lpd = await createLendingPool();

    const lp1 = lpd.createdLendingPoolAddress;
    const lp1_junior = lpd.createdTrancheAddresses[0];
    const lp1_mezzo = lpd.createdTrancheAddresses[1];
    const lp1_senior = lpd.createdTrancheAddresses[1];

    const signers = await hre.ethers.getSigners();
    const alice = signers[1];
    const bob = signers[2];
    const carol = signers[3];
    const david = signers[4];

    // request deposits
    const requestDepositsInput1: RequestDepositInput[] = [
        {
            user: alice,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(1_000_000_000),
        },
        {
            user: bob,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(2_000_000_000),
        },
    ];
    await requestDeposits(requestDepositsInput1);

    // run clearing1
    await runClearing(lp1, clearing1DrawAmount);

    // request deposits
    const requestDepositsInput2: RequestDepositInput[] = [
        {
            user: carol,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(1_000_000_000),
        },
        {
            user: david,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(2_000_000_000),
        },
    ];
    await requestDeposits(requestDepositsInput2);

    // request withdrawals
    const requestWithdrawalsInput1: RequestWithdrawInput[] = [
        {
            user: alice,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            shares: BigInt(200_000_000),
        },
        {
            user: bob,
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            shares: BigInt(8000_000_000),
        },
    ];
    await requestWithdrawals(requestWithdrawalsInput1);

    // run clearing2
    await runClearing(lp1, clearing2DrawAmount);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
