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
import { ContractTransactionResponse, parseEther, Signer } from 'ethers';
import { SystemVariablesSetupStruct } from '../typechain-types/src/core/SystemVariables';
import { addressFileFactory } from './utils/_logs';
import { deployFactory, deployOptions } from './utils/_deploy';
import hre from 'hardhat';
import { addLockPeriods } from './utils/addLockPeriods';

// config values
export const wEthAddress = '0x4200000000000000000000000000000000000006';
const NEXERA_ID_SIGNER = '0x0BAd9DaD98143b2E946e8A40E4f27537be2f55E2';
let PROTOCOL_FEE_RECEIVER = '';

function isLocalDeployment() {
    return (
        hre.network.name === 'localhost' || hre.network.name === 'hardhat'
    );
}


async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = addressFileFactory(
        blockNumber,
        hre.network.name,
    );

    const isNewDeployment = !addressFile.didFileInitiallyExist;
    console.log(`Is new deployment: ${isNewDeployment}`);

    // get signers
    const signers = await hre.ethers.getSigners();

    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();

    const adminSigner = signers[0];
    const adminAddress = await adminSigner.getAddress();

    if (PROTOCOL_FEE_RECEIVER === '') {
        PROTOCOL_FEE_RECEIVER = adminAddress;
    }

    console.log();
    console.log('deployer account: ', deployerAddress);
    console.log('admin account: ', adminAddress);
    console.log();

    const { deployTransparentProxy, deployBeacon } = await deployFactory(
        addressFile,
        isNewDeployment
    );

    // deploy
    let tx: ContractTransactionResponse;
    const ksuDeploymentAddress = await deployTransparentProxy(
        'KSU',
        deployOptions(deployerAddress, []),
    );
    const ksu = KSU__factory.connect(ksuDeploymentAddress, adminSigner);


    const mockUsdcDeploymentAddress = await deployTransparentProxy(
        'MockUSDC',
        deployOptions(deployerAddress, []),
        'USDC',
    );
    const mockUsdc = MockUSDC__factory.connect(
        mockUsdcDeploymentAddress,
        adminSigner,
    );


    const kasuControllerDeploymentAddress = await deployTransparentProxy(
        'KasuController',
        deployOptions(deployerAddress, []),
    );

    const ksuLockingDeploymentAddress = await deployTransparentProxy(
        'KSULocking',
        deployOptions(deployerAddress, [kasuControllerDeploymentAddress]),
    );
    const ksuLocking = KSULocking__factory.connect(
        ksuLockingDeploymentAddress,
        adminSigner,
    );


    const mockKsuPriceDeploymentAddress = await deployTransparentProxy(
        'MockKsuPrice',
        deployOptions(adminAddress, []),
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
              deployOptions(deployerAddress, [
                  mockKsuPriceDeploymentAddress,
                  kasuControllerDeploymentAddress,
              ]),
              'SystemVariables',
          )
        : await deployTransparentProxy(
              'SystemVariables',
              deployOptions(deployerAddress, [
                  mockKsuPriceDeploymentAddress,
                  kasuControllerDeploymentAddress,
              ]),
          );

    const userLoyaltyRewardsDeployment = await deployTransparentProxy(
        'UserLoyaltyRewards',
        deployOptions(deployerAddress, [
            mockKsuPriceDeploymentAddress,
            ksuDeploymentAddress,
            kasuControllerDeploymentAddress,
        ]),
    );

    const userManagerDeploymentAddress = await deployTransparentProxy(
        'UserManager',
        deployOptions(deployerAddress, [
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
        deployOptions(deployerAddress, [kasuControllerDeploymentAddress]),
    );

    const lendingPoolManagerDeploymentAddress = await deployTransparentProxy(
        'LendingPoolManager',
        deployOptions(deployerAddress, [
            mockUsdcDeploymentAddress,
            kasuControllerDeploymentAddress,
            wEthAddress,
            swapperProxyAddress,
        ]),
    );

    const feeManagerDeploymentAddress = await deployTransparentProxy(
        'FeeManager',
        deployOptions(deployerAddress, [
            mockUsdcDeploymentAddress,
            systemVariablesDeploymentAddress,
            kasuControllerDeploymentAddress,
            ksuLockingDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
        ]),
    );

    const kasuAllowListDeploymentAddress = await deployTransparentProxy(
        'KasuAllowList',
        deployOptions(deployerAddress, [kasuControllerDeploymentAddress]),
    );
    const kasuAllowList = KasuAllowList__factory.connect(
        kasuAllowListDeploymentAddress,
        adminSigner,
    );


    // clearing
    const clearingCoordinatorDeploymentAddress = await deployTransparentProxy(
        'ClearingCoordinator',
        deployOptions(adminAddress, [
            systemVariablesDeploymentAddress,
            userManagerDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
        ]),
    );

    const acceptedRequestsCalculationDeployment = await deployTransparentProxy(
        'AcceptedRequestsCalculation',
        deployOptions(adminAddress, []),
    );

    // beacons

    const lendingPoolBeaconAddress = await deployBeacon(
        'LendingPool',
        deployOptions(deployerAddress, [
            systemVariablesDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
            clearingCoordinatorDeploymentAddress,
            feeManagerDeploymentAddress,
            mockUsdcDeploymentAddress,
        ]),
    );

    const pendingPoolBeaconAddress = await deployBeacon(
        'PendingPool',
        deployOptions(deployerAddress, [
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
        deployOptions(deployerAddress, [
            lendingPoolManagerDeploymentAddress,
            mockUsdcDeploymentAddress,
        ]),
    );

    const lendingPoolFactoryAddress = await deployTransparentProxy(
        'LendingPoolFactory',
        deployOptions(deployerAddress, [
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
        deployOptions(deployerAddress, []),
    );

    // initialize
    if(isNewDeployment) {
        tx = await ksu.initialize(adminAddress);
        await tx.wait(1);

        tx = await mockUsdc.initialize();
        await tx.wait(1);

        tx = await ksuLocking.initialize(
            ksuDeploymentAddress,
            mockUsdcDeploymentAddress,
        );
        await tx.wait(1);

        tx = await userManager.initialize(lendingPoolManagerDeploymentAddress);
        await tx.wait(1);

        tx = await kasuAllowList.initialize(
            lendingPoolManagerDeploymentAddress,
            NEXERA_ID_SIGNER,
        );
        await tx.wait(1);

        const kasuController = KasuController__factory.connect(
            kasuControllerDeploymentAddress,
            adminSigner,
        );
        tx = await kasuController.initialize(adminAddress, lendingPoolFactoryAddress);
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
    }


    // add lock periods
    if(isNewDeployment) {
        let tx = await ksuLocking.setCanEmitFees(feeManagerDeploymentAddress, true);
        await tx.wait(1);

        await addLockPeriods(ksuLocking, ksuLockBonusDeploymentAddress);
    }
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
