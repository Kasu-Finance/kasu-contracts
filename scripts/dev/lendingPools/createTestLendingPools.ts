import {
    createLendingPool,
    getDefaultLendingPoolConfig,
} from '../../_modules/createLendingPool';

async function main() {
    await createLendingPool(
        await getDefaultLendingPoolConfig('lending pool 1', 'LP', 3),
    );
    await createLendingPool(
        await getDefaultLendingPoolConfig('lending pool 2', 'LP', 2),
    );
    await createLendingPool(
        await getDefaultLendingPoolConfig('lending pool 3', 'LP', 1),
    );
    await createLendingPool(
        await getDefaultLendingPoolConfig('lending pool 4', 'LP', 3),
    );
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
