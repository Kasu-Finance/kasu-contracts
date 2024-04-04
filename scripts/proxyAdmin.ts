import {
    ProxyAdmin__factory,
    TransparentUpgradeableProxy__factory,
} from '../typechain-types';
import fs from 'fs';
import path from 'path';
import * as hre from 'hardhat';

async function main() {
    // signers
    const namedSigners = await hre.ethers.getNamedSigners();
    const admin = namedSigners['admin'];

    const deploymentAddressesPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );

    const deploymentAddresses = JSON.parse(
        fs.readFileSync(deploymentAddressesPath).toString(),
    );

    const userManagerTUP = TransparentUpgradeableProxy__factory.connect(
        deploymentAddresses.UserManager.address,
        admin,
    );

    const adminChangedQuery = await userManagerTUP.queryFilter(
        userManagerTUP.filters.AdminChanged,
    );

    console.log(adminChangedQuery[0].args);

    const proxyAdmin1 = ProxyAdmin__factory.connect(
        adminChangedQuery[0].args[1],
        admin,
    );
    const owner1 = await proxyAdmin1.owner();
    console.log('Owner1 is admin owner', owner1 == admin.address);

    const proxyAdmin2 = ProxyAdmin__factory.connect(owner1, admin);
    const owner2 = await proxyAdmin2.owner();
    console.log('Owner2 is admin owner', owner2 == admin.address);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
