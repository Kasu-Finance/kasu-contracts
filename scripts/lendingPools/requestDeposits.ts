import {
    RequestDepositInput,
    requestDeposits,
} from '../_modules/requestDeposit';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';

const lendingPoolAddress = '0xBf5A316F4303e13aE92c56D2D8C9F7629bEF5c6e';
const juniorTrancheAddress = '0xbA94C268049DD87Ded35F41F6D4C7542b4BdB767';
const mezzoTrancheAddress = '0x72c1e366E34aC57376BC71Bda0C093b89ADB57Ee';
const seniorTrancheAddress = '';

async function main() {
    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[1];
    const alice = signers[2];
    const bob = signers[3];
    const carol = signers[4];
    const david = signers[5];

    // request deposits
    const requestDepositsInput1: RequestDepositInput[] = [
        {
            user: alice,
            lendingPoolAddress: lendingPoolAddress,
            trancheAddress: juniorTrancheAddress,
            amount: hre.ethers.parseUnits('1000', 6),
            ftdConfigId: 0n,
        },
        {
            user: bob,
            lendingPoolAddress: lendingPoolAddress,
            trancheAddress: mezzoTrancheAddress,
            amount: hre.ethers.parseUnits('2000', 6),
            ftdConfigId: 0n,
        },
    ];
    await requestDeposits(requestDepositsInput1);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
