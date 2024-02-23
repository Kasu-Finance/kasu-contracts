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
