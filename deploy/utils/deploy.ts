import { DeployOptions, DeployResult } from 'hardhat-deploy/types';
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

export function deployFactory(
    hre: HardhatRuntimeEnvironment,
    addressFile: ReturnType<typeof addressFileFactory>,
) {
    return {
        deployWithExportAddress: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            console.log(name, JSON.stringify(options, null, 2));
            const deployment = await hre.deployments.deploy(name, options);
            exportName = exportName ? exportName : name;
            addressFile.writeAddress(exportName, deployment.address);
            return deployment;
        },
    };
}
