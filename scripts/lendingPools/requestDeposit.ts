import {
    RequestDepositInput,
    requestDeposits,
} from '../_modules/requestDeposit';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';

const lendingPoolAddress = '0xBf5A316F4303e13aE92c56D2D8C9F7629bEF5c6e';
const juniorTrancheAddress = '0xbA94C268049DD87Ded35F41F6D4C7542b4BdB767';
const mezzoTrancheAddress = '';
const seniorTrancheAddress = '';

async function main() {
    // signers
    const signers = await getAccounts(hre.network.name);
    const alice = signers[1];
    const bob = signers[2];
    const carol = signers[3];
    const david = signers[4];

    // request deposits
    const requestDepositsInput1: RequestDepositInput[] = [
        {
            user: alice,
            lendingPoolAddress: lendingPoolAddress,
            trancheAddress: juniorTrancheAddress,
            amount: BigInt(1_000_000_000),
        },
        {
            user: bob,
            lendingPoolAddress: lendingPoolAddress,
            trancheAddress: juniorTrancheAddress,
            amount: BigInt(2_000_000_000),
        },
    ];
    await requestDeposits(requestDepositsInput1);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
