import {
    grantLendingPoolRole,
    ROLE_POOL_CLEARING_MANAGER,
} from '../_modules/grantLendingPoolRole';

const LENDING_POOL_ADDRESS = '0xB93c239690061228110525AA16622345241B388e';
const ACCOUNT_ADDRESS = '0x68ea8544AA64479c592711205B59F92122E0893c';

export async function main() {
    // TODO: continue here
    await grantLendingPoolRole(
        LENDING_POOL_ADDRESS,
        ACCOUNT_ADDRESS,
        ROLE_POOL_CLEARING_MANAGER,
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
