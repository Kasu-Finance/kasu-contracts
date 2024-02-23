import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { KSULocking__factory } from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { createAddressFile } from './utils/export-addresses';
import { transparentProxyDeployOptions } from './utils/deploy-options';

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
    const { deploy } = hre.deployments;
    const { admin } = await hre.getNamedAccounts();

    if (!fs.existsSync(path.join(`./deployments/${hre.network.name}`))) {
        fs.mkdirSync(path.join(`./deployments/${hre.network.name}`), {
            recursive: true,
        });
    }

    deploymentPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    blockNumber = await hre.ethers.provider.getBlockNumber();

    const addressFile = createAddressFile(
        deploymentPath,
        blockNumber,
        hre.network.name,
    );

    const proxyAdminDeployment = await deploy('ProxyAdmin', {
        deterministicDeployment: true,
        args: [admin],
        from: admin,
        log: true,
        contract: 'ProxyAdmin',
    });
    const proxyAdmin = proxyAdminDeployment.address;

    addressFile.writeAddress('ProxyAdmin', proxyAdmin);

    const ksu = await deploy(
        'KSU',
        transparentProxyDeployOptions(admin, [admin]),
    );

    addressFile.writeAddressProxy('KSU', ksu.address, ksu.implementation);

    const mockUsdc = await deploy(
        'MockUSDC',
        transparentProxyDeployOptions(admin, [admin]),
    );

    addressFile.writeAddressProxy(
        'USDC',
        mockUsdc.address,
        mockUsdc.implementation,
    );

    const kasuController = await deploy(
        'KasuController',
        transparentProxyDeployOptions(admin, [admin]),
    );

    addressFile.writeAddressProxy(
        'KasuController',
        kasuController.address,
        kasuController.implementation,
    );

    const ksuLockingResult = await deploy(
        'KSULocking',
        transparentProxyDeployOptions(
            admin,
            [ksu.address, mockUsdc.address],
            [kasuController.address],
        ),
    );

    addressFile.writeAddressProxy(
        'KSULocking',
        ksuLockingResult.address,
        ksuLockingResult.implementation,
    );

    const ksuBonusResult = await deploy(
        'KSULockBonus',
        transparentProxyDeployOptions(admin, [
            ksuLockingResult.address,
            ksu.address,
        ]),
    );

    [ksuLockingResult.address, ksu.address];

    addressFile.writeAddressProxy(
        'KSULockBonus',
        ksuBonusResult.address,
        ksuBonusResult.implementation,
    );

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

export default func;
