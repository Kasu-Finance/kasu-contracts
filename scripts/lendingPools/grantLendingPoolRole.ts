import {
    grantLendingPoolRole,
    ROLE_POOL_MANAGER,
} from '../_modules/grantLendingPoolRole';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { requireEnv } from '../_utils/env';

// Required environment variables:
// LENDING_POOL_ADDRESS - address of the lending pool
// ACCOUNT_ADDRESS - address of the account to grant the role to
const LENDING_POOL_ADDRESS = requireEnv('LENDING_POOL_ADDRESS');
const ACCOUNT_ADDRESS = requireEnv('ACCOUNT_ADDRESS');

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
