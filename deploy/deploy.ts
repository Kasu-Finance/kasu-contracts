import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import {
    KasuAllowList__factory,
    KasuController__factory,
    KSULocking__factory,
    LendingPoolManager__factory,
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

    const ksuDeployment = await deployTransparentProxy(
        'KSU',
        deployOptions(deployer, [], [admin]),
    );

    const mockUsdcDeployment = await deployTransparentProxy(
        'MockUSDC',
        deployOptions(deployer, [], [admin]),
        'USDC',
    );

    const kasuControllerDeployment = await deployTransparentProxy(
        'KasuController',
        deployOptions(deployer, []),
    );

    const ksuLockingDeployment = await deployTransparentProxy(
        'KSULocking',
        deployOptions(
            deployer,
            [kasuControllerDeployment.address],
            [ksuDeployment.address, mockUsdcDeployment.address],
        ),
    );

    const kasuAllowListDeployment = await deployTransparentProxy(
        'KasuAllowList',
        deployOptions(deployer, [kasuControllerDeployment.address]),
    );

    const mockKsuPriceDeployment = await deployTransparentProxy(
        'MockKsuPrice',
        deployOptions(admin, [], []),
        'KsuPrice',
    );

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

    // get signer
    const adminSigners = await hre.ethers.getNamedSigners();
    const adminSigner = adminSigners['admin'];

    let tx: ContractTransactionResponse;
    // initialise
    const kasuController = KasuController__factory.connect(
        kasuControllerDeployment.address,
        adminSigner,
    );
    tx = await kasuController.initialize(admin, lendingPoolFactory.address);
    await tx.wait();

    const lendingPoolManager = LendingPoolManager__factory.connect(
        lendingPoolManagerDeployment.address,
        adminSigner,
    );
    tx = await lendingPoolManager.initialize(
        lendingPoolFactory.address,
        kasuAllowListDeployment.address,
    );
    await tx.wait();

    // add lock periods
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingDeployment.address,
        adminSigner,
    );

    tx = await ksuLocking.setKSULockBonus(ksuLockBonusDeployment.address);
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

    // add users to allow list
    const { alice, bob, carol, david } = await hre.getNamedAccounts();
    const kasuAllowList = KasuAllowList__factory.connect(
        kasuAllowListDeployment.address,
        adminSigner,
    );
    await (await kasuAllowList.allowUser(alice)).wait();
    await (await kasuAllowList.allowUser(bob)).wait();
    await (await kasuAllowList.allowUser(carol)).wait();
    await (await kasuAllowList.allowUser(david)).wait();
};

export default func;
