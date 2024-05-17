import fs from 'fs';
import path from 'path';
import hre from 'hardhat';

export function getLogFilePath(networkName: string) {
    const folderPath = path.join(__dirname, '..', '..', '.openzeppelin');
    const filePath = path.join(folderPath, `${networkName}-addresses.json`);

    return { folderPath, filePath };
}

export function addressFileFactory(blockNumber: number, networkName: string) {
    const { filePath } = getLogFilePath(networkName);

    const didFileInitiallyExist = fileExists(filePath);

    if (!didFileInitiallyExist) {
        fs.writeFileSync(
            filePath,
            JSON.stringify({
                network: networkName,
                startBlock: blockNumber,
            }),
        );
    }

    return {
        writeAddressProxy: (
            name: string,
            proxy: string,
            implementation: string,
            proxyType: string,
        ) =>
            writeAddressProxy(
                filePath,
                blockNumber,
                name,
                proxy,
                implementation,
                proxyType,
            ),
        didFileInitiallyExist: didFileInitiallyExist,
        getContractAddresses: () =>
            JSON.parse(fs.readFileSync(filePath).toString()),
        getContractAddress: (contractName: string) =>
            getContractAddress(filePath, contractName),
    };
}

function writeAddressProxy(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    proxy: string,
    implementation: string,
    proxyType: string,
) {
    const addresses = JSON.parse(fs.readFileSync(deploymentPath).toString());
    addresses[name] = {
        address: proxy,
        implementation: implementation,
        startBlock: blockNumber,
        proxyType: proxyType,
    };
    fs.writeFileSync(deploymentPath, JSON.stringify(addresses, null, 4));
}

function fileExists(filePath: string): boolean {
    try {
        fs.accessSync(filePath);
        return true;
    } catch (error) {
        return false;
    }
}

function getContractAddress(
    deploymentPath: string,
    contractName: string,
): string {
    const addresses = JSON.parse(fs.readFileSync(deploymentPath).toString());
    const address = addresses[contractName].address;
    if (address == undefined || address == '') {
        console.error(
            'Could not find address for deployment',
            deploymentPath,
            contractName,
        );
        throw new Error();
    }
    return address;
}
