import {
    KasuAllowList__factory,
    KasuController__factory,
    KSU__factory,
    KSULocking__factory,
    LendingPoolManager__factory,
    MockKsuPrice__factory,
    MockUSDC__factory,
    SystemVariables__factory,
    UserManager__factory,
} from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { ContractTransactionResponse, parseEther } from 'ethers';
import { SystemVariablesSetupStruct } from '../typechain-types/src/core/SystemVariables';
import { addressFileFactory } from './utils/_logs';
import { deployFactory, deployOptions } from './utils/_deploy';
import hre from 'hardhat';
import { addLockPeriods } from './utils/addLockPeriods';

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

export const wEthAddress = '0x4200000000000000000000000000000000000006';

let deploymentPath = path.join('./deployment-addresses-none.json');
let blockNumber = 0;
const NEXERA_ID_SIGNER = '0x0BAd9DaD98143b2E946e8A40E4f27537be2f55E2';

let PROTOCOL_FEE_RECEIVER = '';

async function main() {
    if (!fs.existsSync(path.join(`./deployments/${hre.network.name}`))) {
        fs.mkdirSync(path.join(`./deployments/${hre.network.name}`), {
            recursive: true,
        });
    }
    deploymentPath = path.join(
        `./deployments/${hre.network.name}/addresses-${hre.network.name}.json`,
    );
    blockNumber = await hre.ethers.provider.getBlockNumber();

    const isLocalDeployment = () => {
        return (
            hre.network.name === 'localhost' || hre.network.name === 'hardhat'
        );
    };

    const addressFile = addressFileFactory(
        deploymentPath,
        blockNumber,
        hre.network.name,
    );

    const signers = await hre.ethers.getSigners();
    const deployer = signers[0].address;
    const admin = signers[0].address;

    if (PROTOCOL_FEE_RECEIVER === '') {
        PROTOCOL_FEE_RECEIVER = admin;
    }

    console.log();
    console.log('deployer account: ', deployer);
    console.log('admin account: ', admin);
    console.log();

    const { deployTransparentProxy, deployBeacon } = await deployFactory(
        addressFile,
    );

    // get signer
    const singers = await hre.ethers.getSigners();
    const adminSigner = singers[0];

    // deploy
    let tx: ContractTransactionResponse;
    const ksuDeploymentAddress = await deployTransparentProxy(
        'KSU',
        deployOptions(deployer, []),
    );
    const ksu = KSU__factory.connect(ksuDeploymentAddress, adminSigner);
    tx = await ksu.initialize(admin);
    await tx.wait(1);

    const mockUsdcDeploymentAddress = await deployTransparentProxy(
        'MockUSDC',
        deployOptions(deployer, []),
        'USDC',
    );
    const mockUsdc = MockUSDC__factory.connect(
        mockUsdcDeploymentAddress,
        adminSigner,
    );
    tx = await mockUsdc.initialize();
    await tx.wait(1);

    const kasuControllerDeploymentAddress = await deployTransparentProxy(
        'KasuController',
        deployOptions(deployer, []),
    );

    const ksuLockingDeploymentAddress = await deployTransparentProxy(
        'KSULocking',
        deployOptions(deployer, [kasuControllerDeploymentAddress]),
    );
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingDeploymentAddress,
        adminSigner,
    );
    tx = await ksuLocking.initialize(
        ksuDeploymentAddress,
        mockUsdcDeploymentAddress,
    );
    await tx.wait(1);

    const mockKsuPriceDeploymentAddress = await deployTransparentProxy(
        'MockKsuPrice',
        deployOptions(admin, []),
        'KsuPrice',
    );
    const mockKsuPriceAddress = MockKsuPrice__factory.connect(
        mockKsuPriceDeploymentAddress,
        adminSigner,
    );
    tx = await mockKsuPriceAddress.setKsuTokenPrice(parseEther('2'));
    await tx.wait(1);

    const systemVariablesDeploymentAddress = isLocalDeployment()
        ? await deployTransparentProxy(
              'SystemVariablesTestable',
              deployOptions(deployer, [
                  mockKsuPriceDeploymentAddress,
                  kasuControllerDeploymentAddress,
              ]),
              'SystemVariables',
          )
        : await deployTransparentProxy(
              'SystemVariables',
              deployOptions(deployer, [
                  mockKsuPriceDeploymentAddress,
                  kasuControllerDeploymentAddress,
              ]),
          );

    const feeManagerDeploymentAddress = await deployTransparentProxy(
        'FeeManager',
        deployOptions(deployer, [
            mockUsdcDeploymentAddress,
            systemVariablesDeploymentAddress,
            kasuControllerDeploymentAddress,
            ksuLockingDeploymentAddress,
        ]),
    );

    const userLoyaltyRewardsDeployment = await deployTransparentProxy(
        'UserLoyaltyRewards',
        deployOptions(deployer, [
            mockKsuPriceDeploymentAddress,
            ksuDeploymentAddress,
            kasuControllerDeploymentAddress,
        ]),
    );

    const userManagerDeploymentAddress = await deployTransparentProxy(
        'UserManager',
        deployOptions(deployer, [
            systemVariablesDeploymentAddress,
            ksuLockingDeploymentAddress,
            userLoyaltyRewardsDeployment,
        ]),
    );
    const userManager = UserManager__factory.connect(
        userManagerDeploymentAddress,
        adminSigner,
    );

    const swapperProxyAddress = await deployTransparentProxy(
        'Swapper',
        deployOptions(deployer, [kasuControllerDeploymentAddress]),
    );

    const lendingPoolManagerDeploymentAddress = await deployTransparentProxy(
        'LendingPoolManager',
        deployOptions(deployer, [
            mockUsdcDeploymentAddress,
            kasuControllerDeploymentAddress,
            wEthAddress,
            swapperProxyAddress,
        ]),
    );

    tx = await userManager.initialize(lendingPoolManagerDeploymentAddress);
    await tx.wait(1);

    const kasuAllowListDeploymentAddress = await deployTransparentProxy(
        'KasuAllowList',
        deployOptions(deployer, [kasuControllerDeploymentAddress]),
    );
    const kasuAllowList = KasuAllowList__factory.connect(
        kasuAllowListDeploymentAddress,
        adminSigner,
    );
    tx = await kasuAllowList.initialize(
        lendingPoolManagerDeploymentAddress,
        NEXERA_ID_SIGNER,
    );
    await tx.wait(1);

    // clearing
    const clearingCoordinatorDeploymentAddress = await deployTransparentProxy(
        'ClearingCoordinator',
        deployOptions(admin, [
            systemVariablesDeploymentAddress,
            userManagerDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
        ]),
    );

    const acceptedRequestsCalculationDeployment = await deployTransparentProxy(
        'AcceptedRequestsCalculation',
        deployOptions(admin, []),
    );

    // beacons

    const lendingPoolBeaconAddress = await deployBeacon(
        'LendingPool',
        deployOptions(deployer, [
            systemVariablesDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
            clearingCoordinatorDeploymentAddress,
            feeManagerDeploymentAddress,
            mockUsdcDeploymentAddress,
        ]),
    );

    const pendingPoolBeaconAddress = await deployBeacon(
        'PendingPool',
        deployOptions(deployer, [
            systemVariablesDeploymentAddress,
            mockUsdcDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
            userManagerDeploymentAddress,
            clearingCoordinatorDeploymentAddress,
            acceptedRequestsCalculationDeployment,
        ]),
    );

    const lendingPoolTrancheBeaconAddress = await deployBeacon(
        'LendingPoolTranche',
        deployOptions(deployer, [
            lendingPoolManagerDeploymentAddress,
            mockUsdcDeploymentAddress,
        ]),
    );

    const lendingPoolFactoryAddress = await deployTransparentProxy(
        'LendingPoolFactory',
        deployOptions(deployer, [
            pendingPoolBeaconAddress,
            lendingPoolBeaconAddress,
            lendingPoolTrancheBeaconAddress,
            kasuControllerDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
            systemVariablesDeploymentAddress,
        ]),
    );

    const ksuLockBonusDeploymentAddress = await deployTransparentProxy(
        'KSULockBonus',
        deployOptions(deployer, []),
    );

    // initialize
    const kasuController = KasuController__factory.connect(
        kasuControllerDeploymentAddress,
        adminSigner,
    );
    tx = await kasuController.initialize(admin, lendingPoolFactoryAddress);
    await tx.wait(1);

    const lendingPoolManager = LendingPoolManager__factory.connect(
        lendingPoolManagerDeploymentAddress,
        adminSigner,
    );
    tx = await lendingPoolManager.initialize(
        lendingPoolFactoryAddress,
        kasuAllowListDeploymentAddress,
        userManagerDeploymentAddress,
        clearingCoordinatorDeploymentAddress,
    );
    await tx.wait(1);

    const systemVariables = SystemVariables__factory.connect(
        systemVariablesDeploymentAddress,
        adminSigner,
    );
    const systemVariablesSetup: SystemVariablesSetupStruct = {
        initialEpochStartTimestamp:
            Math.round(Date.now() / 1000) - 3600 * 24 * 4,
        clearingPeriodLength: 60 * 60 * 36,
        performanceFee: 10_00,
        loyaltyThresholds: [10_00, 30_00],
        defaultTrancheInterestChangeEpochDelay: 1,
        ecosystemFeeRate: 50_00,
        protocolFeeRate: 50_00,
        protocolFeeReceiver: PROTOCOL_FEE_RECEIVER,
    };
    console.info('Initializing System Variables', PROTOCOL_FEE_RECEIVER);
    tx = await systemVariables.initialize(systemVariablesSetup);
    await tx.wait(1);
    console.log('System Variables initialized');

    // add lock periods
    await addLockPeriods(ksuLocking, ksuLockBonusDeploymentAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
