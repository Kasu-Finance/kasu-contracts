import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
    KasuController__factory,
    KSU__factory,
    KSULocking__factory,
    LendingPoolManager__factory,
    MockKsuPrice__factory,
    MockUSDC__factory,
} from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { addressFileFactory } from './utils/export-addresses';
import { deployFactory, deployOptions } from './utils/deploy';
import { ContractTransactionResponse } from 'ethers';

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

    // get signer
    const adminSigners = await hre.ethers.getNamedSigners();
    const adminSigner = adminSigners['admin'];

    // deploy
    let tx: ContractTransactionResponse;
    const ksuDeployment = await deployTransparentProxy(
        'KSU',
        deployOptions(deployer, []),
    );
    const ksu = KSU__factory.connect(ksuDeployment.address, adminSigner);
    tx = await ksu.initialize(admin);
    await tx.wait(1);

    const mockUsdcDeployment = await deployTransparentProxy(
        'MockUSDC',
        deployOptions(deployer, []),
        'USDC',
    );
    const mockUsdc = MockUSDC__factory.connect(
        mockUsdcDeployment.address,
        adminSigner,
    );
    tx = await mockUsdc.initialize(admin);
    await tx.wait(1);

    const kasuControllerDeployment = await deployTransparentProxy(
        'KasuController',
        deployOptions(deployer, []),
    );

    const ksuLockingDeployment = await deployTransparentProxy(
        'KSULocking',
        deployOptions(deployer, [kasuControllerDeployment.address]),
    );
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingDeployment.address,
        adminSigner,
    );
    tx = await ksuLocking.initialize(
        ksuDeployment.address,
        mockUsdcDeployment.address,
    );
    await tx.wait(1);

    const kasuAllowListDeployment = await deployTransparentProxy(
        'KasuAllowList',
        deployOptions(deployer, [kasuControllerDeployment.address]),
    );

    const mockKsuPriceDeployment = await deployTransparentProxy(
        'MockKsuPrice',
        deployOptions(admin, []),
        'KsuPrice',
    );
    const mockKsuPrice = MockKsuPrice__factory.connect(
        mockKsuPriceDeployment.address,
        adminSigner,
    );
    tx = await mockKsuPrice.initialize();
    await tx.wait(1);

    const systemVariablesDeployment = await deployTransparentProxy(
        'SystemVariables',
        deployOptions(deployer, [
            mockKsuPriceDeployment.address,
            kasuControllerDeployment.address,
        ]),
    );

    const lendingPoolManagerDeployment = await deployTransparentProxy(
        'LendingPoolManager',
        deployOptions(deployer, [
            mockUsdcDeployment.address,
            kasuControllerDeployment.address,
        ]),
    );

    const userManagerDeployment = await deployTransparentProxy(
        'UserManager',
        deployOptions(deployer, [
            systemVariablesDeployment.address,
            ksuLockingDeployment.address,
        ]),
    );

    const pendingPoolBeacon = await deployBeacon(
        'PendingPool',
        deployOptions(deployer, [
            systemVariablesDeployment.address,
            mockUsdcDeployment.address,
            lendingPoolManagerDeployment.address,
            userManagerDeployment.address,
        ]),
    );

    const lendingPoolBeacon = await deployBeacon(
        'LendingPool',
        deployOptions(deployer, [
            systemVariablesDeployment.address,
            mockUsdcDeployment.address,
        ]),
    );

    const lendingPoolTrancheBeacon = await deployBeacon(
        'LendingPoolTranche',
        deployOptions(deployer, [lendingPoolManagerDeployment.address]),
    );

    const lendingPoolFactory = await deployTransparentProxy(
        'LendingPoolFactory',
        deployOptions(deployer, [
            pendingPoolBeacon.address,
            lendingPoolBeacon.address,
            lendingPoolTrancheBeacon.address,
            kasuControllerDeployment.address,
            lendingPoolManagerDeployment.address,
        ]),
    );

    const ksuLockBonusDeployment = await deployTransparentProxy(
        'KSULockBonus',
        deployOptions(deployer, []),
    );

    // initialise
    const kasuController = KasuController__factory.connect(
        kasuControllerDeployment.address,
        adminSigner,
    );
    tx = await kasuController.initialize(admin, lendingPoolFactory.address);
    await tx.wait(1);

    const lendingPoolManager = LendingPoolManager__factory.connect(
        lendingPoolManagerDeployment.address,
        adminSigner,
    );
    tx = await lendingPoolManager.initialize(
        lendingPoolFactory.address,
        kasuAllowListDeployment.address,
    );
    await tx.wait(1);

    // add lock periods
    tx = await ksuLocking.setKSULockBonus(ksuLockBonusDeployment.address);
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod30,
        lockMultiplier30,
        ksuBonusMultiplier30,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod180,
        lockMultiplier180,
        ksuBonusMultiplier180,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod360,
        lockMultiplier360,
        ksuBonusMultiplier360,
    );
    await tx.wait(1);

    tx = await ksuLocking.addLockPeriod(
        lockPeriod720,
        lockMultiplier720,
        ksuBonusMultiplier720,
    );
    await tx.wait(1);
};

export default func;
