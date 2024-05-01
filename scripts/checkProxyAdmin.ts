import {
    ProxyAdmin__factory,
    TransparentUpgradeableProxy__factory,
} from '../typechain-types';
import fs from 'fs';
import path from 'path';
import * as hre from 'hardhat';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';

async function main() {
    const deploymentAddressesPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );

    const deploymentAddresses = JSON.parse(
        fs.readFileSync(deploymentAddressesPath).toString(),
    );

    const signers = await hre.ethers.getSigners();
    const adminSigner = signers[0];

    console.log('Admin address:', adminSigner.address);
    console.log('ProxyAdmin address:', deploymentAddresses.ProxyAdmin.address);
    console.log();

    const systemVariablesProxy = TransparentUpgradeableProxy__factory.connect(
        deploymentAddresses.SystemVariables.address,
        adminSigner,
    );

    const adminChangedFilter =
        systemVariablesProxy.filters['AdminChanged(address,address)'];

    const adminChangedFilterEvents = await systemVariablesProxy.queryFilter(
        adminChangedFilter,
    );

    adminChangedFilterEvents.forEach((event) => {
        console.log('SystemVariables:AdminChanged:OldAdmin:', event.args[0]);
        console.log('SystemVariables:AdminChanged:NewAdmin:', event.args[1]);
    });

    console.log(
        `SystemVariables' ProxyAdmin is ${adminChangedFilterEvents[0].args[1]}`,
    );

    const events1 = await logProxyAdminOwnershipTransferredEvent(
        adminChangedFilterEvents[0].args[1],
        adminSigner,
    );

    const events2 = await logProxyAdminOwnershipTransferredEvent(
        deploymentAddresses.ProxyAdmin.address,
        adminSigner,
    );

    console.log('is correct:', events1[0].args[1] == adminSigner.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

async function logProxyAdminOwnershipTransferredEvent(
    proxyAdminAddress: string,
    signer: HardhatEthersSigner,
) {
    const proxyAdmin = ProxyAdmin__factory.connect(proxyAdminAddress, signer);

    const ownershipTransferredFilter =
        proxyAdmin.filters['OwnershipTransferred(address,address)'];

    const ownershipTransferredEvents = await proxyAdmin.queryFilter(
        ownershipTransferredFilter,
    );

    console.log();
    console.log('ProxyAdmin address:', proxyAdminAddress);
    ownershipTransferredEvents.forEach((event) => {
        console.log('OwnershipTransferred:OldAdmin:', event.args[0]);
        console.log('OwnershipTransferred:NewAdmin:', event.args[1]);
    });

    return ownershipTransferredEvents;
}
