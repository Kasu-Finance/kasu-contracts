import { SystemVariablesTestable__factory } from '../../typechain-types';
import { getLogFilePath } from '../_utils/_logs';
import * as hre from 'hardhat';
import fs from 'fs';
import { ethers } from 'ethers';
import * as systemVariablesAbi from '../../out/SystemVariables.sol/SystemVariables.json';
import { getAccounts } from '../_utils/getAccounts';

async function main() {
    try {
        await task();
    } catch (error: any) {
        // decoding error based on ABI
        const iface = new ethers.Interface([...systemVariablesAbi.abi]);
        const parsedError = iface.parseError(error.data);
        if (!parsedError) {
            console.error(`Could not parse error.`);
            throw error;
        }
        console.error(`Error name: ${parsedError.name}`);
        console.error(`Error args: ${JSON.stringify(parsedError.args)}`);
    }
}

async function task() {
    // contract addresses
    const { filePath } = getLogFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await getAccounts(hre.network.name);
    const admin = signers[0];

    console.log(`Admin: ${await admin.getAddress()}`);

    const systemVariablesTestable = SystemVariablesTestable__factory.connect(
        deploymentAddresses.SystemVariables.address,
        admin,
    );

    let tx;

    // start clearing period
    console.log('Manually start clearing period');
    tx = await systemVariablesTestable.startClearing();
    await tx.wait(1);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
