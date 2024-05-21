import { runClearing } from '../_modules/runClearing';
import { parseUnits } from 'ethers';
import * as hre from 'hardhat';
import { getAccounts } from '../_modules/getAccounts';

const lendingPoolAddress = '0xBf5A316F4303e13aE92c56D2D8C9F7629bEF5c6e';
const drawAmount = parseUnits('500', 6);

async function main() {
    const signers = await getAccounts(hre.network.name);
    const clearingManagerAccount = signers[1];

    await runClearing(lendingPoolAddress, drawAmount, clearingManagerAccount);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
