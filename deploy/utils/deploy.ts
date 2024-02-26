import { DeployOptions, DeployResult } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { addressFileFactory } from './export-addresses';

export function transparentProxyDeployOptions(
    admin: string,
    initializeArgs: unknown[],
    constructorArgs: unknown[] = [],
) {
    return {
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
            const deployment = await hre.deployments.deploy(name, options);
            exportName = exportName ? exportName : name;
            addressFile.writeAddress(exportName, deployment.address);
            return deployment;
        },
    };
}
