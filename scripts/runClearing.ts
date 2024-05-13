import { runClearing } from './utils/runClearing';
import { parseUnits } from 'ethers';

const LENDING_POOL_ADDRESS = '';
const DRAW_AMOUNT = parseUnits('0', 6);

async function main() {
    await runClearing(LENDING_POOL_ADDRESS, DRAW_AMOUNT);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
