import { Address, DeployOptions, DeployResult } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { addressFileFactory } from './export-addresses';

export function deployOptions(
    deployer: string,
    constructorArgs: unknown[],
    initializeArgs?: unknown[],
): DeployOptions {
    let config: DeployOptions = {
        deterministicDeployment: true,
        from: deployer,
        args: constructorArgs,
        log: true,
    };

    if (initializeArgs !== undefined) {
        config = {
            deterministicDeployment: true,
            from: deployer,
            args: constructorArgs,
            proxy: {
                execute: {
                    methodName: 'initialize',
                    args: initializeArgs,
                },
            },
            log: true,
        };
    }

    return config;
}

export async function deployFactory(
    hre: HardhatRuntimeEnvironment,
    addressFile: ReturnType<typeof addressFileFactory>,
    deployer: Address,
    proxyAdminAdmin: Address,
) {
    const proxyAdmin = await hre.deployments.deploy(
        'ProxyAdmin',
        deployOptions(deployer, [proxyAdminAdmin]),
    );

    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            const implementation = await hre.deployments.deploy(name, options);

            const transparentUpgradeableProxy = await hre.deployments.deploy(
                'TransparentUpgradeableProxy',
                deployOptions(deployer, [
                    implementation.address,
                    proxyAdmin.address,
                    [],
                ]),
            );

            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(
                exportName,
                transparentUpgradeableProxy.address,
                implementation.address,
            );
            return transparentUpgradeableProxy;
        },
        deployBeacon: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            const contractImplementation = await hre.deployments.deploy(
                name,
                options,
            );
            const beaconDeployment = await hre.deployments.deploy(
                'UpgradeableBeacon',
                deployOptions(deployer, [
                    contractImplementation.address,
                    deployer,
                ]),
            );
            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(
                exportName + '_Beacon',
                beaconDeployment.address,
                contractImplementation.address,
            );
            return beaconDeployment;
        },
    };
}
