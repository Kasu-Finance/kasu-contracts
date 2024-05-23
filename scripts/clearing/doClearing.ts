import { parseUnits } from 'ethers';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';
import { doClearing } from '../_modules/doClearing';
import { parseKasuErrors } from '../_utils/parseErrors';

const lendingPoolAddress = '0x2F9c56edD3Ba0a06AA58767f50E52761D85f3Bc7';
const numberOfTranches = 3;
const drawAmount = parseUnits('0', 6);

async function main() {
    const signers = await getAccounts(hre.network.name);
    const clearingManagerAccount = signers[0];

    try {
        await doClearing(
            lendingPoolAddress,
            drawAmount,
            clearingManagerAccount,
            numberOfTranches,
        );
    } catch (error: any) {
        parseKasuErrors(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
