import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { KSULocking__factory } from '../typechain-types';

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

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deploy } = hre.deployments;
    const { admin } = await hre.getNamedAccounts();

    const proxyAdminDeployment = await deploy('ProxyAdmin', {
        deterministicDeployment: true,
        args: [admin],
        from: admin,
        log: true,
    });
    const proxyAdmin = proxyAdminDeployment.address;

    const ksu = await deploy('KSU', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: proxyAdmin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    const mockUsdc = await deploy('MockUSDC', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: proxyAdmin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    const kasuController = await deploy('KasuController', {
        deterministicDeployment: true,
        from: admin,
        proxy: {
            owner: proxyAdmin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [admin],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    const ksuLockingResult = await deploy('KSULocking', {
        deterministicDeployment: true,
        from: admin,
        args: [kasuController.address],
        proxy: {
            owner: proxyAdmin,
            execute: {
                init: {
                    methodName: 'initialize',
                    args: [ksu.address, mockUsdc.address],
                },
            },
            proxyContract: 'OpenZeppelinTransparentProxy',
        },
        log: true,
    });

    // add lock periods
    const adminSigners = await hre.ethers.getNamedSigners();
    const adminSigner = adminSigners['admin'];
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingResult.address,
        adminSigner,
    );
    let tx = await ksuLocking.addLockPeriod(
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

export default func;
