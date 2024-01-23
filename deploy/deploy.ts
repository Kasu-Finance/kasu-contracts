import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { KSULocking__factory } from '../typechain-types';
import fs from 'fs';
import path from 'path';

export const SECONDS_IN_DAY = 86400n;

export const lockPeriod30 = 30n * SECONDS_IN_DAY;
export const lockMultiplier30 = 5_00;
export const ksuBonusMultiplier30 = 0;

export const lockPeriod180 = 180n * SECONDS_IN_DAY;
export const lockMultiplier180 = 25_00;
export const ksuBonusMultiplier180 = 10_00;

export const lockPeriod360 = 360n * SECONDS_IN_DAY;
export const lockMultiplier360 = 50_00;
export const ksuBonusMultiplier360 = 25_00;

export const lockPeriod720 = 720n * SECONDS_IN_DAY;
export const lockMultiplier720 = 100_00;
export const ksuBonusMultiplier720 = 70_00;

let deploymentPath = path.join("./deployment-addresses-none.json");
let blockNumber = 0;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy } = hre.deployments;
    const { admin } = await hre.getNamedAccounts();

    if (!fs.existsSync(path.join(`./deployments/${hre.network.name}`))) {
        fs.mkdirSync(path.join(`./deployments/${hre.network.name}`), { recursive: true });
    }

    deploymentPath = path.join(`./deployments/${hre.network.name}/addresses-${hre.network.name}.json`);
    blockNumber = await hre.ethers.provider.getBlockNumber();

    fs.writeFileSync(deploymentPath, JSON.stringify({
        network: hre.network.name,
        startBlock: blockNumber,
    }));

    const proxyAdminDeployment = await deploy('ProxyAdmin', {
        deterministicDeployment: true,
        args: [admin],
        from: admin,
        log: true,
        contract: 'ProxyAdmin',
    });
    const proxyAdmin = proxyAdminDeployment.address;

    writeAddress('ProxyAdmin', proxyAdmin);

    const ksu = await deploy('KSU', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: admin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    });

    writeAddressProxy('KSU', ksu.address, ksu.implementation);

    const mockUsdc = await deploy('MockUSDC', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: admin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    });

    writeAddressProxy('USDC', mockUsdc.address, mockUsdc.implementation);

    const kasuController = await deploy('KasuController', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: admin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    });

    writeAddressProxy('KasuController', kasuController.address, kasuController.implementation);

    const ksuLockingResult = await deploy('KSULocking', {
        deterministicDeployment: true,
        from: admin,
        args: [kasuController.address],
        proxy: {
            owner: admin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [ksu.address, mockUsdc.address],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    });

    writeAddressProxy('KSULocking', ksuLockingResult.address, ksuLockingResult.implementation);

    const ksuBonusResult = await deploy('KSULockBonus', {
        deterministicDeployment: true,
        from: admin,
        args: [],
        proxy: {
            owner: admin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [ksuLockingResult.address, ksu.address],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
            viaAdminContract: 'ProxyAdmin',
        },
        log: true,
    });

    writeAddressProxy('KSULockBonus', ksuBonusResult.address, ksuBonusResult.implementation);

    // add lock periods
    const adminSigners = await hre.ethers.getNamedSigners();
    const adminSigner = adminSigners['admin'];
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingResult.address,
        adminSigner,
    );

    let tx = await ksuLocking.setKSULockBonus(ksuBonusResult.address);
    await tx.wait();

    tx = await ksuLocking.addLockPeriod(
        lockPeriod30,
        lockMultiplier30,
        ksuBonusMultiplier30,
    );
    await tx.wait();
    tx = await ksuLocking.addLockPeriod(
        lockPeriod180,
        lockMultiplier180,
        ksuBonusMultiplier180,
    );
    await tx.wait();
    tx = await ksuLocking.addLockPeriod(
        lockPeriod360,
        lockMultiplier360,
        ksuBonusMultiplier360,
    );
    await tx.wait();
    tx = await ksuLocking.addLockPeriod(
        lockPeriod720,
        lockMultiplier720,
        ksuBonusMultiplier720,
    );
    await tx.wait();
};

function writeAddressProxy(name: string, proxy: string, implementation: string | undefined = undefined) {
    if (implementation) {
        _writeAddress(name, implementation, proxy);
    } else {
        throw new Error(`Implementation address for ${name} is undefined`);
    }
}

function writeAddress(name: string, implementation: string) {
    _writeAddress(name, implementation);
}

function _writeAddress(name: string, implementation: string, proxy: string | undefined = undefined) {
    const addresses = JSON.parse((fs.readFileSync(deploymentPath)).toString());

    if (!proxy) {
        addresses[name] = {
            address: implementation,
            startBlock: blockNumber,
        };
    } else {
        addresses[name] = {
            address: proxy,
            implementation: implementation,
            startBlock: blockNumber,
        };
    }

    fs.writeFileSync(deploymentPath, JSON.stringify(addresses, null, 4));
}

export default func;
