import { runClearing } from './utils/runClearing';
import { parseUnits } from 'ethers';

const LENDING_POOL_ADDRESS = '0xD90cfCf44330968e5574116C41b80d699222F317';
const DRAW_AMOUNT = parseUnits('0', 6);

async function main() {
    // run clearing1
    await runClearing(LENDING_POOL_ADDRESS, DRAW_AMOUNT);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
