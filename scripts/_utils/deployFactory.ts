import { deploymentFileFactory } from './deploymentFileFactory';
import hre, { ethers, upgrades } from 'hardhat';
import { DeployProxyOptions } from '@openzeppelin/hardhat-upgrades/src/utils';
import { Signer } from 'ethers';

export function deployOptions(
    deployer: string,
    constructorArgs: unknown[],
    kind: 'transparent' | 'beacon' = 'transparent',
): DeployProxyOptions {
    return {
        initializer: false,
        initialOwner: deployer,
        constructorArgs: constructorArgs,
        redeployImplementation: 'onchange',
        verifySourceCode: false,
        kind: kind,
        unsafeAllow: ['constructor', 'state-variable-immutable'],
    };
}

async function verifyImplementation(
    address: string,
    constructorArgs: unknown[] | undefined,
) {
    try {
        await hre.run('verify:verify', {
            address,
            constructorArguments: constructorArgs ?? [],
        });
    } catch (e) {
        console.error(e);
    }
}

export async function deployFactory(
    addressFile: ReturnType<typeof deploymentFileFactory>,
    isNewDeployment: boolean,
    deployUpdates: boolean,
    verifySource: boolean,
    deployer: Signer,
) {
    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(
                name,
                deployer,
            );

            exportName = exportName ? exportName : name;

            let proxyAddress = '';
            let deployedImplementationAddress = '';

            if (isNewDeployment) {
                console.log(`Deploying ${name} contract`);
                const proxy = await upgrades.deployProxy(
                    implementation,
                    options,
                );
                await proxy.waitForDeployment();

                proxyAddress = await proxy.getAddress();

                deployedImplementationAddress =
                    await upgrades.erc1967.getImplementationAddress(
                        proxyAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    proxyAddress,
                    deployedImplementationAddress,
                    'TransparentProxy',
                );

                if (verifySource && deployedImplementationAddress) {
                    await verifyImplementation(
                        deployedImplementationAddress,
                        options.constructorArgs,
                    );
                }
            }

            if (!isNewDeployment && deployUpdates) {
                console.log(`Checking to update ${name} contract`);
                proxyAddress = addressFile.getContractAddress(exportName);

                const newImplementationAddress = (await upgrades.prepareUpgrade(
                    proxyAddress,
                    implementation,
                    options,
                )).toString();

                deployedImplementationAddress =
                    await upgrades.erc1967.getImplementationAddress(
                        proxyAddress,
                    );

                if (
                    newImplementationAddress !== deployedImplementationAddress
                ) {
                    console.log('Performing upgrade');
                    const proxy = await upgrades.upgradeProxy(
                        proxyAddress,
                        implementation,
                        options,
                    );
                    await proxy.waitForDeployment();

                    deployedImplementationAddress =
                        await upgrades.erc1967.getImplementationAddress(
                            proxyAddress,
                        );
                }

                const implementationToWrite =
                    deployedImplementationAddress || newImplementationAddress;
                addressFile.writeAddressProxy(
                    exportName,
                    proxyAddress,
                    implementationToWrite,
                    'TransparentProxy',
                );

                if (verifySource && implementationToWrite) {
                    await verifyImplementation(
                        implementationToWrite,
                        options.constructorArgs,
                    );
                }
            }

            return proxyAddress;
        },

        deployBeacon: async (
            name: string,
            options: DeployProxyOptions,
            exportName?: string,
        ): Promise<string> => {
            const implementation = await ethers.getContractFactory(
                name,
                deployer,
            );

            exportName = exportName ? exportName : name;

            let beaconAddress = '';
            let deployedImplementationAddress = '';

            if (isNewDeployment) {
                console.log(`Deploying ${name} contract`);
                const beacon = await upgrades.deployBeacon(
                    implementation,
                    options,
                );
                await beacon.waitForDeployment();

                beaconAddress = await beacon.getAddress();

                deployedImplementationAddress =
                    await upgrades.beacon.getImplementationAddress(
                        beaconAddress,
                    );

                addressFile.writeAddressProxy(
                    exportName,
                    beaconAddress,
                    deployedImplementationAddress,
                    'BeaconProxy',
                );

                if (verifySource && deployedImplementationAddress) {
                    await verifyImplementation(
                        deployedImplementationAddress,
                        options.constructorArgs,
                    );
                }
            }

            if (!isNewDeployment && deployUpdates) {
                console.log(`Checking to update ${name} contract`);
                beaconAddress = addressFile.getContractAddress(exportName);

                const newImplementationAddress = (await upgrades.prepareUpgrade(
                    beaconAddress,
                    implementation,
                    options,
                )).toString();

                deployedImplementationAddress =
                    await upgrades.beacon.getImplementationAddress(
                        beaconAddress,
                    );

                if (
                    newImplementationAddress !== deployedImplementationAddress
                ) {
                    console.log('Performing upgrade');

                    const proxy = await upgrades.upgradeBeacon(
                        beaconAddress,
                        implementation,
                        options,
                    );
                    beaconAddress = await proxy.getAddress();

                    deployedImplementationAddress =
                        await upgrades.beacon.getImplementationAddress(
                            beaconAddress,
                        );
                }

                const implementationToWrite =
                    deployedImplementationAddress || newImplementationAddress;
                addressFile.writeAddressProxy(
                    exportName,
                    beaconAddress,
                    implementationToWrite,
                    'BeaconProxy',
                );

                if (verifySource && implementationToWrite) {
                    await verifyImplementation(
                        implementationToWrite,
                        options.constructorArgs,
                    );
                }
            }

            return beaconAddress;
        },
    };
}
