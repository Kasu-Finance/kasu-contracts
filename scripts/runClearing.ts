import { runClearing } from './utils/runClearing';
import { parseUnits } from 'ethers';

const lendingPoolAddress = '';
const drawAmount = parseUnits('0', 6);

async function main() {
    await runClearing(lendingPoolAddress, drawAmount);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
