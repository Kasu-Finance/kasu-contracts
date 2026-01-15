import {
    FixedTermDeposit__factory,
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

type DeploymentMode = 'full' | 'lite';

// config values
const DEFAULT_WRAPPED_NATIVE_ADDRESS =
    '0x4200000000000000000000000000000000000006';
const DEFAULT_NEXERA_ID_SIGNER =
    '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0';
const DEFAULT_PROTOCOL_FEE_RECEIVER = '';
const DEFAULT_USDC_ADDRESS =
    '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';

const LOCAL_NETWORKS = new Set(['localhost', 'hardhat']);

function resolveBooleanEnv(name: string, defaultValue: boolean): boolean {
    const rawValue = process.env[name];
    if (!rawValue) {
        return defaultValue;
    }
    return rawValue.toLowerCase() === 'true';
}

async function main() {
    const blockNumber = await hre.ethers.provider.getBlockNumber();
    const addressFile = deploymentFileFactory(hre.network.name, blockNumber);

    const isNewDeployment = !addressFile.didFileInitiallyExist;
    console.log(`Is new deployment: ${isNewDeployment}`);

    // get signers
    const signers = await getAccounts(hre.network.name);

    const deploymentMode = (process.env.DEPLOYMENT_MODE ?? 'full').toLowerCase() as DeploymentMode;
    if (deploymentMode !== 'full' && deploymentMode !== 'lite') {
        throw new Error(`Invalid DEPLOYMENT_MODE: ${deploymentMode}`);
    }
    const isLiteDeployment = deploymentMode === 'lite';
    const isLocalNetwork = LOCAL_NETWORKS.has(hre.network.name);

    const deployMockUSDC = resolveBooleanEnv('DEPLOY_MOCK_USDC', isLocalNetwork);
    const deploySystemVariablesTestable = resolveBooleanEnv(
        'DEPLOY_SYSTEM_VARIABLES_TESTABLE',
        isLocalNetwork,
    );
    const deployUpdates = resolveBooleanEnv('DEPLOY_UPDATES', isLocalNetwork);
    const verifySource = resolveBooleanEnv('VERIFY_SOURCE', !isLocalNetwork);

    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();

    const adminSigner = signers[1];
    const adminAddress = await adminSigner.getAddress();

    const nexeraIdSigner =
        process.env.NEXERA_ID_SIGNER ?? DEFAULT_NEXERA_ID_SIGNER;
    const wrappedNativeAddress =
        process.env.WRAPPED_NATIVE_ADDRESS ?? DEFAULT_WRAPPED_NATIVE_ADDRESS;
    let protocolFeeReceiver =
        process.env.PROTOCOL_FEE_RECEIVER ?? DEFAULT_PROTOCOL_FEE_RECEIVER;
    let usdcAddress = process.env.USDC_ADDRESS ?? DEFAULT_USDC_ADDRESS;

    if (protocolFeeReceiver === '') {
        protocolFeeReceiver = adminAddress;
    }

    console.log();
    console.log('deployer account: ', deployerAddress);
    console.log('admin account: ', adminAddress);
    console.log(`deployment mode: ${isLiteDeployment ? 'Lite' : 'Full'}`);
    console.log('deploy mock usdc: ', deployMockUSDC);
    console.log('deploy system variables testable: ', deploySystemVariablesTestable);
    console.log('deploy updates: ', deployUpdates);
    console.log('verify source: ', verifySource);
    console.log('wrapped native: ', wrappedNativeAddress);
    console.log();

    const { deployTransparentProxy, deployBeacon } = await deployFactory(
        addressFile,
        isNewDeployment,
        deployUpdates,
        verifySource,
        deployerSigner,
    );

    // deploy
    let tx: ContractTransactionResponse;
    let ksuDeploymentAddress = '';
    let ksu:
        | ReturnType<typeof KSU__factory.connect>
        | undefined;

    if (!isLiteDeployment) {
        ksuDeploymentAddress = await deployTransparentProxy(
            'KSU',
            deployOptions(deployerAddress, []),
        );
        ksu = KSU__factory.connect(ksuDeploymentAddress, adminSigner);
    }

    if (deployMockUSDC) {
        usdcAddress = await deployTransparentProxy(
            'MockUSDC',
            deployOptions(deployerAddress, []),
            'USDC',
        );
        const usdc = MockUSDC__factory.connect(usdcAddress, adminSigner);
        tx = await usdc.initialize();
        await tx.wait(1);
    } else {
        const existingAddresses = addressFile.getContractAddresses();
        if (!existingAddresses.USDC?.address) {
            addressFile.writeAddress('USDC', usdcAddress);
        }
    }

    const kasuControllerDeploymentAddress = await deployTransparentProxy(
        'KasuController',
        deployOptions(deployerAddress, []),
    );

    const ksuLockingDeploymentAddress = await deployTransparentProxy(
        isLiteDeployment ? 'KSULockingLite' : 'KSULocking',
        deployOptions(
            deployerAddress,
            isLiteDeployment ? [] : [kasuControllerDeploymentAddress],
        ),
        'KSULocking',
    );
    const ksuLocking = !isLiteDeployment
        ? KSULocking__factory.connect(ksuLockingDeploymentAddress, adminSigner)
        : undefined;

    let ksuPriceDeploymentAddress = '';
    if (isLiteDeployment) {
        ksuPriceDeploymentAddress = await deployTransparentProxy(
            'KsuPriceLite',
            deployOptions(adminAddress, []),
            'KsuPrice',
        );
    } else {
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
        ksuPriceDeploymentAddress = manualKsuPriceDeploymentAddress;
    }

    let systemVariablesDeploymentAddress;
    if (deploySystemVariablesTestable) {
        console.log('Deploying SystemVariablesTestable...');
        systemVariablesDeploymentAddress = await deployTransparentProxy(
            'SystemVariablesTestable',
            deployOptions(deployerAddress, [
                ksuPriceDeploymentAddress,
                kasuControllerDeploymentAddress,
            ]),
            'SystemVariables',
        );
    } else {
        console.log('Deploying SystemVariables...');
        systemVariablesDeploymentAddress = await deployTransparentProxy(
            'SystemVariables',
            deployOptions(deployerAddress, [
                ksuPriceDeploymentAddress,
                kasuControllerDeploymentAddress,
            ]),
        );
    }

    const fixedTermDepositAddress = await deployTransparentProxy(
        'FixedTermDeposit',
        deployOptions(deployerAddress, [systemVariablesDeploymentAddress]),
    );

    const fixedTermDeposit = FixedTermDeposit__factory.connect(
        fixedTermDepositAddress,
        adminSigner,
    )

    const userLoyaltyRewardsDeploymentAddress = await deployTransparentProxy(
        isLiteDeployment ? 'UserLoyaltyRewardsLite' : 'UserLoyaltyRewards',
        deployOptions(
            deployerAddress,
            isLiteDeployment
                ? []
                : [
                      ksuPriceDeploymentAddress,
                      ksuDeploymentAddress,
                      kasuControllerDeploymentAddress,
                  ],
        ),
        'UserLoyaltyRewards',
    );

    const userManagerDeploymentAddress = await deployTransparentProxy(
        isLiteDeployment ? 'UserManagerLite' : 'UserManager',
        deployOptions(deployerAddress, [
            systemVariablesDeploymentAddress,
            ksuLockingDeploymentAddress,
            userLoyaltyRewardsDeploymentAddress,
        ]),
        'UserManager',
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
            fixedTermDepositAddress,
            usdcAddress,
            kasuControllerDeploymentAddress,
            wrappedNativeAddress,
            swapperProxyAddress,
        ]),
    );

    const feeManagerDeploymentAddress = await deployTransparentProxy(
        isLiteDeployment ? 'ProtocolFeeManagerLite' : 'FeeManager',
        deployOptions(deployerAddress, [
            usdcAddress,
            systemVariablesDeploymentAddress,
            kasuControllerDeploymentAddress,
            ksuLockingDeploymentAddress,
            lendingPoolManagerDeploymentAddress,
        ]),
        'FeeManager',
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
            fixedTermDepositAddress,
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
        deployOptions(
            deployerAddress,
            [
                systemVariablesDeploymentAddress,
                lendingPoolManagerDeploymentAddress,
                clearingCoordinatorDeploymentAddress,
                feeManagerDeploymentAddress,
                fixedTermDepositAddress,
                usdcAddress,
            ],
            'beacon',
        ),
    );

    const pendingPoolBeaconAddress = await deployBeacon(
        'PendingPool',
        deployOptions(
            deployerAddress,
            [
                systemVariablesDeploymentAddress,
                usdcAddress,
                lendingPoolManagerDeploymentAddress,
                userManagerDeploymentAddress,
                clearingCoordinatorDeploymentAddress,
                acceptedRequestsCalculationDeployment,
                fixedTermDepositAddress,
            ],
            'beacon',
        ),
    );

    const lendingPoolTrancheBeaconAddress = await deployBeacon(
        'LendingPoolTranche',
        deployOptions(
            deployerAddress,
            [userManagerDeploymentAddress, fixedTermDepositAddress, lendingPoolManagerDeploymentAddress, usdcAddress],
            'beacon',
        ),
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

    const userLoyaltyRewards = !isLiteDeployment
        ? UserLoyaltyRewards__factory.connect(
              userLoyaltyRewardsDeploymentAddress,
              adminSigner,
          )
        : undefined;

    // initialize
    if (isNewDeployment) {
        if (!isLiteDeployment && ksu && ksuLocking) {
            tx = await ksu.initialize(adminAddress);
            await tx.wait(1);

            tx = await ksuLocking.initialize(ksuDeploymentAddress, usdcAddress);
            await tx.wait(1);
        }

        tx = await userManager.initialize(lendingPoolManagerDeploymentAddress);
        await tx.wait(1);

        tx = await kasuAllowList.initialize(
            lendingPoolManagerDeploymentAddress,
            nexeraIdSigner,
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

        tx = await fixedTermDeposit.initialize(lendingPoolManagerDeploymentAddress, clearingCoordinatorDeploymentAddress);

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
            loyaltyThresholds: isLiteDeployment ? [] : [1_00, 5_00],
            defaultTrancheInterestChangeEpochDelay: 4,
            ecosystemFeeRate: 0,
            protocolFeeRate: 100_00,
            protocolFeeReceiver: protocolFeeReceiver,
        };
        console.info('Initializing System Variables', adminAddress);
        tx = await systemVariables.initialize(systemVariablesSetup);
        await tx.wait(1);
        console.log('System Variables initialized');

        if (!isLiteDeployment && userLoyaltyRewards) {
            tx = await userLoyaltyRewards.initialize(
                userManagerDeploymentAddress,
                true,
            );
            await tx.wait(1);
        }
    }

    // initial values
    if (isNewDeployment && !isLiteDeployment && ksuLocking && userLoyaltyRewards) {
        tx = await ksuLocking.setCanEmitFees(
            feeManagerDeploymentAddress,
            true,
        );
        await tx.wait(1);

        tx = await ksuLocking.setCanSetFeeRecipient(
            userManagerDeploymentAddress,
            true,
        );
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
