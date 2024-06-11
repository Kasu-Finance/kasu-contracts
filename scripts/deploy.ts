import {
    KasuAllowList__factory,
    KasuController__factory,
    KSU__factory,
    KSULocking__factory,
    LendingPoolManager__factory,
    ManualKsuPrice__factory,
    MockUSDC__factory,
    SystemVariables__factory,
    UserLoyaltyRewards__factory,
    UserManager__factory,
} from '../typechain-types';
import { ContractTransactionResponse, parseEther } from 'ethers';
import { SystemVariablesSetupStruct } from '../typechain-types/src/core/SystemVariables';
import { deploymentFileFactory } from './_utils/deploymentFileFactory';
import { deployFactory, deployOptions } from './_utils/deployFactory';
import hre from 'hardhat';
import { addLockPeriods } from './_modules/addLockPeriods';
import { getAccounts } from './_modules/getAccounts';

// config values
export const wEthAddress = '0x4200000000000000000000000000000000000006';
const NEXERA_ID_SIGNER = '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0';
let PROTOCOL_FEE_RECEIVER = '0x0e7e0a898ddBbE859d08976dE1673c7A9F579483';
let USDC_ADDRESS = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';
const deploySystemVariablesTestable = false;
const verifySource = true;
const deployUpdates = false;

async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

    const isNewDeployment = !addressFile.didFileInitiallyExist;
    console.log(`Is new deployment: ${isNewDeployment}`);

    // get signers
    const signers = await getAccounts(hre.network.name);

    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();

    const adminSigner = signers[1];
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
        isNewDeployment,
        deployUpdates,
        verifySource,
    );

    // deploy
    let tx: ContractTransactionResponse;
    const ksuDeploymentAddress = await deployTransparentProxy(
        'KSU',
        deployOptions(deployerAddress, []),
    );
    const ksu = KSU__factory.connect(ksuDeploymentAddress, adminSigner);

    let usdcAddress = USDC_ADDRESS;
    if (USDC_ADDRESS === '') {
        usdcAddress = await deployTransparentProxy(
            'MockUSDC',
            deployOptions(deployerAddress, []),
            'USDC',
        );
        const usdc = MockUSDC__factory.connect(usdcAddress, adminSigner);
        tx = await usdc.initialize();
        await tx.wait(1);
    }

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

    const manualKsuPriceDeploymentAddress = await deployTransparentProxy(
        'ManualKsuPrice',
        deployOptions(adminAddress, []),
        'KsuPrice',
    );
    const manualKsuPriceAddress = ManualKsuPrice__factory.connect(
        manualKsuPriceDeploymentAddress,
        adminSigner,
    );
    tx = await manualKsuPriceAddress.setKsuTokenPrice(parseEther('2'));
    await tx.wait(1);

    let systemVariablesDeploymentAddress;
    if (deploySystemVariablesTestable) {
        console.log('Deploying SystemVariablesTestable...');
        systemVariablesDeploymentAddress = await deployTransparentProxy(
            'SystemVariablesTestable',
            deployOptions(deployerAddress, [
                manualKsuPriceDeploymentAddress,
                kasuControllerDeploymentAddress,
            ]),
            'SystemVariables',
        );
    } else {
        console.log('Deploying SystemVariables...');
        systemVariablesDeploymentAddress = await deployTransparentProxy(
            'SystemVariables',
            deployOptions(deployerAddress, [
                manualKsuPriceDeploymentAddress,
                kasuControllerDeploymentAddress,
            ]),
        );
    }

    const userLoyaltyRewardsDeploymentAddress = await deployTransparentProxy(
        'UserLoyaltyRewards',
        deployOptions(deployerAddress, [
            manualKsuPriceDeploymentAddress,
            ksuDeploymentAddress,
            kasuControllerDeploymentAddress,
        ]),
    );

    const userManagerDeploymentAddress = await deployTransparentProxy(
        'UserManager',
        deployOptions(deployerAddress, [
            systemVariablesDeploymentAddress,
            ksuLockingDeploymentAddress,
            userLoyaltyRewardsDeploymentAddress,
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
            usdcAddress,
            kasuControllerDeploymentAddress,
            wEthAddress,
            swapperProxyAddress,
        ]),
    );

    const feeManagerDeploymentAddress = await deployTransparentProxy(
        'FeeManager',
        deployOptions(deployerAddress, [
            usdcAddress,
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
            usdcAddress,
        ]),
    );

    const pendingPoolBeaconAddress = await deployBeacon(
        'PendingPool',
        deployOptions(deployerAddress, [
            systemVariablesDeploymentAddress,
            usdcAddress,
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
            usdcAddress,
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

    const userLoyaltyRewards = UserLoyaltyRewards__factory.connect(
        userLoyaltyRewardsDeploymentAddress,
        adminSigner,
    );

    // initialize
    if (isNewDeployment) {
        tx = await ksu.initialize(adminAddress);
        await tx.wait(1);

        tx = await ksuLocking.initialize(ksuDeploymentAddress, usdcAddress);
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
        tx = await kasuController.initialize(
            adminAddress, // KASU_ADMIN
            lendingPoolFactoryAddress,
        );
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
            // Math.round(Date.now() / 1000) - 3600 * 24 * 4
            initialEpochStartTimestamp: 1717653600,
            clearingPeriodLength: 3600 * 48,
            performanceFee: 10_00,
            loyaltyThresholds: [1_00, 5_00],
            defaultTrancheInterestChangeEpochDelay: 4,
            ecosystemFeeRate: 0,
            protocolFeeRate: 100_00,
            protocolFeeReceiver: adminAddress,
        };
        console.info('Initializing System Variables', adminAddress);
        tx = await systemVariables.initialize(systemVariablesSetup);
        await tx.wait(1);
        console.log('System Variables initialized');

        tx = await userLoyaltyRewards.initialize(
            userManagerDeploymentAddress,
            true,
        );
        await tx.wait(1);
    }

    // initial values
    if (isNewDeployment) {
        tx = await ksuLocking.setCanEmitFees(feeManagerDeploymentAddress, true);
        await tx.wait(1);

        tx = await userLoyaltyRewards.setRewardRatesPerLoyaltyLevel([
            { loyaltyLevel: 1, epochRewardRate: 19164956034632 }, // 0.1% / 52.17857 epochs/years * 10^18
            { loyaltyLevel: 2, epochRewardRate: 38329912069265 }, // 0.2% / 52.17857 epochs/years * 10^18
        ]);
        await tx.wait(1);

        await addLockPeriods(ksuLocking, ksuLockBonusDeploymentAddress);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
