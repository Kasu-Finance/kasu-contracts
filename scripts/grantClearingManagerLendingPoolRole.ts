import {
    grantLendingPoolRole,
    ROLE_POOL_CLEARING_MANAGER,
} from './utils/grantLendingPoolRole';

const LENDING_POOL_ADDRESS = '0x2F9c56edD3Ba0a06AA58767f50E52761D85f3Bc7';
const ACCOUNT_ADDRESS = '0x97cbcD33f1075070e59F354E4eCf71Ed6267E1ED';

export async function main() {
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
