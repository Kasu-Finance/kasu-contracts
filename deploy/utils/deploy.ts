import { Address, DeployOptions, DeployResult } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { addressFileFactory } from './export-addresses';

export function transparentProxyDeployOptions(
    admin: string,
    constructorArgs: unknown[],
    initializeArgs: unknown[] | undefined,
): DeployOptions {
    let config: DeployOptions = {
        deterministicDeployment: true,
        from: admin,
        args: constructorArgs,
        proxy: {
            owner: admin,
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    };

    if (initializeArgs !== undefined) {
        config = {
            deterministicDeployment: true,
            from: admin,
            args: constructorArgs,
            proxy: {
                owner: admin,
                execute: {
                    init: {
                        methodName: 'initialize',
                        args: initializeArgs,
                    },
                },
                proxyContract: 'OpenZeppelinTransparentProxy',
                viaAdminContract: 'ProxyAdmin',
            },
            log: true,
        };
    }

    return config;
}

export function upgradeableBeaconDeployOptions(
    admin: string,
    constructorArgs: unknown[],
): DeployOptions {
    return {
        deterministicDeployment: true,
        from: admin,
        args: constructorArgs,
        log: true,
    };
}

export function deployFactory(
    hre: HardhatRuntimeEnvironment,
    addressFile: ReturnType<typeof addressFileFactory>,
    admin: Address,
) {
    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            const deployment = await hre.deployments.deploy(name, options);
            exportName = exportName ? exportName : name;
            addressFile.writeAddress(exportName, deployment.address);
            return deployment;
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
                {
                    deterministicDeployment: true,
                    from: admin,
                    args: [contractImplementation.address, admin],
                    log: true,
                },
            );
            exportName = exportName ? exportName : name;
            addressFile.writeAddress(exportName, beaconDeployment.address);
            addressFile.writeAddress(
                exportName + '_Beacon',
                beaconDeployment.address,
            );
            return beaconDeployment;
        },
    };
}
