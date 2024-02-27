import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { KSULocking__factory } from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { addressFileFactory } from './utils/export-addresses';
import {
    deployFactory,
    transparentProxyDeployOptions,
    upgradeableBeaconDeployOptions,
} from './utils/deploy';

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

let deploymentPath = path.join('./deployment-addresses-none.json');
let blockNumber = 0;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    if (!fs.existsSync(path.join(`./deployments/${hre.network.name}`))) {
        fs.mkdirSync(path.join(`./deployments/${hre.network.name}`), {
            recursive: true,
        });
    }
    deploymentPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    blockNumber = await hre.ethers.provider.getBlockNumber();

    const addressFile = addressFileFactory(
        deploymentPath,
        blockNumber,
        hre.network.name,
    );

    const { admin } = await hre.getNamedAccounts();
    const deployer = admin;

    const { deployTransparentProxy, deployBeacon } = await deployFactory(
        hre,
        addressFile,
        deployer,
        admin,
    );

    const ksuDeployment = await deployTransparentProxy(
        'KSU',
        transparentProxyDeployOptions(deployer, [], [admin]),
    );

    const mockUsdcDeployment = await deployTransparentProxy(
        'MockUSDC',
        transparentProxyDeployOptions(deployer, [], [admin]),
        'USDC',
    );

    const kasuControllerDeployment = await deployTransparentProxy(
        'KasuController',
        transparentProxyDeployOptions(deployer, [], undefined),
    );

    const ksuLockingDeployment = await deployTransparentProxy(
        'KSULocking',
        transparentProxyDeployOptions(
            deployer,
            [kasuControllerDeployment.address],
            [ksuDeployment.address, mockUsdcDeployment.address],
        ),
    );

    await deployTransparentProxy(
        'KasuAllowList',
        transparentProxyDeployOptions(
            deployer,
            [kasuControllerDeployment.address],
            undefined,
        ),
    );

    const mockKsuPriceDeployment = await deployTransparentProxy(
        'MockKsuPrice',
        transparentProxyDeployOptions(admin, [], []),
        'KsuPrice',
    );

    const systemVariablesDeployment = await deployTransparentProxy(
        'SystemVariables',
        transparentProxyDeployOptions(
            deployer,
            [mockKsuPriceDeployment.address, kasuControllerDeployment.address],
            undefined,
        ),
    );

    const lendingPoolManagerDeployment = await deployTransparentProxy(
        'LendingPoolManager',
        transparentProxyDeployOptions(
            deployer,
            [mockUsdcDeployment.address, kasuControllerDeployment.address],
            undefined,
        ),
    );

    const userManagerDeployment = await deployTransparentProxy(
        'UserManager',
        transparentProxyDeployOptions(
            admin,
            [systemVariablesDeployment.address, ksuLockingDeployment.address],
            undefined,
        ),
    );

    const pendingPoolBeacon = await deployBeacon(
        'PendingPool',
        upgradeableBeaconDeployOptions(admin, [
            systemVariablesDeployment.address,
            mockUsdcDeployment.address,
            lendingPoolManagerDeployment.address,
            userManagerDeployment.address,
        ]),
    );

    const ksuLockBonusDeployment = await deployTransparentProxy(
        'KSULockBonus',
        transparentProxyDeployOptions(
            admin,
            [],
            [ksuLockingDeployment.address, ksuDeployment.address],
        ),
    );

    // add lock periods
    const adminSigners = await hre.ethers.getNamedSigners();
    const adminSigner = adminSigners['admin'];
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingDeployment.address,
        adminSigner,
    );

    let tx = await ksuLocking.setKSULockBonus(ksuLockBonusDeployment.address);
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

export default func;
