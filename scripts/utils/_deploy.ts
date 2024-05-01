import { addressFileFactory } from './_logs';
import { ethers, upgrades } from 'hardhat';
import { DeployProxyOptions } from '@openzeppelin/hardhat-upgrades/src/utils';

export function deployOptions(
    deployer: string,
    constructorArgs: unknown[],
): DeployProxyOptions {
    return {
        initializer: false,
        initialOwner: deployer,
        constructorArgs: constructorArgs,
        redeployImplementation: 'onchange',
        kind: 'transparent',
        unsafeAllow: ['constructor'],
    };
}

export async function deployFactory(
    addressFile: ReturnType<typeof addressFileFactory>,
) {
    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(name);

            const proxy = await upgrades.deployProxy(implementation, options);
            const proxyAddress = await proxy.getAddress();
            console.log(`Deployed ${name} in address ${proxyAddress}}`);

            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(exportName, proxyAddress, '');
            return proxyAddress;
        },
        deployBeacon: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(name);
            const beacon = await upgrades.deployBeacon(implementation, options);
            const beaconAddress = await beacon.getAddress();

            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(
                exportName + '_Beacon',
                await beacon.getAddress(),
                '',
            );
            return beaconAddress;
        },
    };
}
