import { createLendingPool } from './utils/createLendingPool';

async function main() {
    await createLendingPool('lending pool 1', 'LP', 3);
    await createLendingPool('lending pool 2', 'LP', 2);
    await createLendingPool('lending pool 2', 'LP', 1);
    await createLendingPool('lending pool 2', 'LP', 3);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
