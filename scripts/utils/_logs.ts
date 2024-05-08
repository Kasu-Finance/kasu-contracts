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
            implementation: string,
            proxyType: string,
        ) =>
            writeAddressProxy(
                deploymentPath,
                blockNumber,
                name,
                proxy,
                implementation,
                proxyType
            ),
    };
}

function writeAddressProxy(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    proxy: string,
    implementation: string,
    proxyType: string
) {
    _writeAddress(deploymentPath, blockNumber, name, implementation, proxy, proxyType);
}

function _writeAddress(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    implementation: string,
    proxy: string,
    proxyType: string
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
            proxyType: proxyType,
        };
    }

    fs.writeFileSync(deploymentPath, JSON.stringify(addresses, null, 4));
}
