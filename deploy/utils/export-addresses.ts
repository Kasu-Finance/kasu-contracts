import fs from 'fs';

export function addressFileFactory(
    deploymentPath: string,
    blockNumber: number,
    networkName: string,
) {
    fs.writeFileSync(
        deploymentPath,
        JSON.stringify({
            network: networkName,
            startBlock: blockNumber,
        }),
    );

    return {
        writeAddressProxy: (
            name: string,
            proxy: string,
            implementation: string | undefined = undefined,
        ) =>
            writeAddressProxy(
                deploymentPath,
                blockNumber,
                name,
                proxy,
                implementation,
            ),
        writeAddress: (name: string, implementation: string) =>
            writeAddress(deploymentPath, blockNumber, name, implementation),
    };
}

function writeAddressProxy(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    proxy: string,
    implementation: string | undefined = undefined,
) {
    if (implementation) {
        _writeAddress(deploymentPath, blockNumber, name, implementation, proxy);
    } else {
        throw new Error(`Implementation address for ${name} is undefined`);
    }
}

function writeAddress(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    implementation: string,
) {
    _writeAddress(deploymentPath, blockNumber, name, implementation);
}

function _writeAddress(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    implementation: string,
    proxy: string | undefined = undefined,
) {
    const addresses = JSON.parse(fs.readFileSync(deploymentPath).toString());

    if (!proxy) {
        addresses[name] = {
            address: implementation,
            startBlock: blockNumber,
        };
    } else {
        addresses[name] = {
            address: proxy,
            implementation: implementation,
            startBlock: blockNumber,
        };
    }

    fs.writeFileSync(deploymentPath, JSON.stringify(addresses, null, 4));
}
