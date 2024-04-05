import * as hre from 'hardhat';
import { createLendingPool } from './utils/createLendingPool';
import { RequestDepositInput, requestDeposits } from './utils/requestDeposit';
import { runClearing } from './utils/runClearing';

const DRAW_AMOUNT = hre.ethers.parseUnits('2500', 6); // 2500 USDC

async function main() {
    const lpd = await createLendingPool();

    const lp1 = lpd.createdLendingPoolAddress;
    const lp1_junior = lpd.createdTrancheAddresses[0];
    const lp1_mezzo = lpd.createdTrancheAddresses[1];
    const lp1_senior = lpd.createdTrancheAddresses[1];

    const namedSigners = await hre.ethers.getNamedSigners();

    const requestDepositsInput: RequestDepositInput[] = [
        {
            user: namedSigners['alice'],
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(1_000_000_000),
        },
        {
            user: namedSigners['bob'],
            lendingPoolAddress: lp1,
            trancheAddress: lp1_junior,
            amount: BigInt(2_000_000_000),
        },
    ];
    await requestDeposits(requestDepositsInput);
    await runClearing(lp1, DRAW_AMOUNT);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
