import { getAccounts } from '../../_modules/getAccounts';
import * as hre from 'hardhat';
import { addFixedTermDeposit } from '../../_modules/addFixedTermDeposit';
import { requireLocalNetwork } from '../../_utils/env';

async function main() {
    requireLocalNetwork(hre.network.name);
    // signers
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];

    await addFixedTermDeposit(
        "0xeD343c0f99C89Ed7c3c934A88f90261fD6a9A68b",
        {
            tranche: "0x874305DB059EF37C48536F32Dd109b4C7aB60a6d",
            epochLockDuration: 4,
            epochInterestRate: 2_682_121_951_395_655, // 15%
            whitelistedOnly: false
        },
        adminAccount
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
