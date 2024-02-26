import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { KSULocking__factory } from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { addressFileFactory } from './utils/export-addresses';
import { deployFactory, transparentProxyDeployOptions } from './utils/deploy';

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

    const { deployWithExportAddress } = deployFactory(hre, addressFile);

    const { admin } = await hre.getNamedAccounts();

    await deployWithExportAddress('ProxyAdmin', {
        deterministicDeployment: true,
        args: [admin],
        from: admin,
        log: true,
        contract: 'ProxyAdmin',
    });

    const ksu = await deployWithExportAddress(
        'KSU',
        transparentProxyDeployOptions(admin, [admin]),
    );

    const mockUsdc = await deployWithExportAddress(
        'MockUSDC',
        transparentProxyDeployOptions(admin, [admin]),
        'USDC',
    );

    const kasuController = await deployWithExportAddress(
        'KasuController',
        transparentProxyDeployOptions(admin, [admin], []),
    );

    const ksuLockingResult = await deployWithExportAddress(
        'KSULocking',
        transparentProxyDeployOptions(
            admin,
            [ksu.address, mockUsdc.address],
            [kasuController.address],
        ),
    );

    const ksuBonusResult = await deployWithExportAddress(
        'KSULockBonus',
        transparentProxyDeployOptions(admin, [
            ksuLockingResult.address,
            ksu.address,
        ]),
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
