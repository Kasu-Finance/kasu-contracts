import * as hre from 'hardhat';
import { getAccounts } from '../../_modules/getAccounts';
import { startClearing } from '../_modules/startEndClearing';
import { parseKasuError } from '../../_utils/parseErrors';
import { requireLocalNetwork } from '../../_utils/env';

async function main() {
    requireLocalNetwork(hre.network.name);
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];

    try {
        await startClearing(adminAccount);
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
