import {
    grantLendingPoolRole,
    ROLE_POOL_MANAGER,
} from '../_modules/grantLendingPoolRole';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';

const LENDING_POOL_ADDRESS = '0xb93c239690061228110525aa16622345241b388e';
const ACCOUNT_ADDRESS = '0x68ea8544AA64479c592711205B59F92122E0893c';

export async function main() {
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];

    await grantLendingPoolRole(
        LENDING_POOL_ADDRESS,
        ACCOUNT_ADDRESS,
        ROLE_POOL_MANAGER,
        adminAccount,
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
