import {
    grantLendingPoolRole,
    ROLE_POOL_CLEARING_MANAGER,
} from '../_modules/grantLendingPoolRole';

const LENDING_POOL_ADDRESS = '0xBf5A316F4303e13aE92c56D2D8C9F7629bEF5c6e';
const ACCOUNT_ADDRESS = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

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
