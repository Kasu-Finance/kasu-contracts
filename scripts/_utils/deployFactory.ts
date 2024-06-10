import { deploymentFileFactory } from './deploymentFileFactory';
import hre, { ethers, upgrades } from 'hardhat';
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
        verifySourceCode: false,
        kind: 'transparent',
        unsafeAllow: ['constructor', 'state-variable-immutable'],
    };
}

export async function deployFactory(
    addressFile: ReturnType<typeof deploymentFileFactory>,
    isNewDeployment: boolean,
    deployUpdates: boolean,
    verifySource: boolean,
) {
    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(name);

            exportName = exportName ? exportName : name;

            let proxyAddress = '';
            let implementationAddress = '';

            if (isNewDeployment) {
                console.log(`Deploying ${name} contract`);
                const proxy = await upgrades.deployProxy(
                    implementation,
                    options,
                );
                await proxy.waitForDeployment();

                proxyAddress = await proxy.getAddress();

                implementationAddress =
                    await upgrades.erc1967.getImplementationAddress(
                        proxyAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    proxyAddress,
                    implementationAddress,
                    'TransparentProxy',
                );
            }

            if (!isNewDeployment && deployUpdates) {
                console.log(`Checking to update ${name} contract`);
                proxyAddress = addressFile.getContractAddress(exportName);

                const proxy = await upgrades.upgradeProxy(
                    proxyAddress,
                    implementation,
                    options,
                );
                await proxy.waitForDeployment();

                implementationAddress =
                    await upgrades.erc1967.getImplementationAddress(
                        proxyAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    proxyAddress,
                    implementationAddress,
                    'TransparentProxy',
                );
            }

            if (!isNewDeployment && verifySource) {
                proxyAddress = addressFile.getContractAddress(exportName);
                try {
                    await hre.run('verify:verify', {
                        address: proxyAddress,
                        constructorArguments: options.constructorArgs,
                    });
                } catch (e) {
                    console.error(e);
                }
            }

            return proxyAddress;
        },

        deployBeacon: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(name);

            exportName = exportName ? exportName : name;

            let beaconAddress = '';
            let implementationAddress = '';

            if (isNewDeployment) {
                console.log(`Deploying ${name} contract`);
                const beacon = await upgrades.deployBeacon(
                    implementation,
                    options,
                );
                await beacon.waitForDeployment();

                beaconAddress = await beacon.getAddress();

                implementationAddress =
                    await upgrades.beacon.getImplementationAddress(
                        beaconAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    beaconAddress,
                    implementationAddress,
                    'BeaconProxy',
                );
            }

            if (!isNewDeployment && deployUpdates) {
                console.log(`Checking to update ${name} contract`);
                beaconAddress = addressFile.getContractAddress(name);

                const proxy = await upgrades.upgradeBeacon(
                    beaconAddress,
                    implementation,
                    options,
                );
                beaconAddress = await proxy.getAddress();

                implementationAddress =
                    await upgrades.beacon.getImplementationAddress(
                        beaconAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    beaconAddress,
                    implementationAddress,
                    'BeaconProxy',
                );
            }

            if (!isNewDeployment && verifySource) {
                beaconAddress = addressFile.getContractAddress(exportName);
                try {
                    await hre.run('verify:verify', {
                        address: beaconAddress,
                        constructorArguments: options.constructorArgs,
                    });
                } catch (e) {
                    console.error(e);
                }
            }

            return beaconAddress;
        },
    };
}
