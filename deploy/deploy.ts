import { HardhatRuntimeEnvironment } from 'hardhat/types';
import {
    Address,
    DeployFunction,
    DeployOptions,
    DeployResult,
} from 'hardhat-deploy/types';
import {
    KasuAllowList__factory,
    KasuController__factory,
    KSU__factory,
    KSULocking__factory,
    LendingPoolManager__factory,
    MockKsuPrice__factory,
    MockUSDC__factory,
    SystemVariables__factory,
} from '../typechain-types';
import fs from 'fs';
import path from 'path';
import { ContractTransactionResponse } from 'ethers';
import { SystemVariablesSetupStruct } from '../typechain-types/src/core/SystemVariables';

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
const NEXERA_ID_SIGNER = '0x0BAd9DaD98143b2E946e8A40E4f27537be2f55E2';

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

    const isLocalDeployment = () => {
        return hre.network.name === 'localhost' || hre.network.name === 'hardhat';
    };

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

    const systemVariablesDeployment = isLocalDeployment()
        ? await deployTransparentProxy(
              'SystemVariablesTestable',
              deployOptions(deployer, [
                  mockKsuPriceDeployment.address,
                  kasuControllerDeployment.address,
              ]),
              'SystemVariables',
          )
        : await deployTransparentProxy(
              'SystemVariables',
              deployOptions(deployer, [
                  mockKsuPriceDeployment.address,
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

    const lendingPoolManagerDeployment = await deployTransparentProxy(
        'LendingPoolManager',
        deployOptions(deployer, [
            mockUsdcDeployment.address,
            kasuControllerDeployment.address,
        ]),
    );

    const kasuAllowListDeployment = await deployTransparentProxy(
        'KasuAllowList',
        deployOptions(deployer, [kasuControllerDeployment.address]),
    );
    const kasuAllowlist = KasuAllowList__factory.connect(
        kasuAllowListDeployment.address,
        adminSigner,
    );
    tx = await kasuAllowlist.initialize(lendingPoolManagerDeployment.address, NEXERA_ID_SIGNER);
    await tx.wait(1);

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
        deployOptions(deployer, [
            lendingPoolManagerDeployment.address,
            mockUsdcDeployment.address,
        ]),
    );

    const lendingPoolFactory = await deployTransparentProxy(
        'LendingPoolFactory',
        deployOptions(deployer, [
            pendingPoolBeacon.address,
            lendingPoolBeacon.address,
            lendingPoolTrancheBeacon.address,
            kasuControllerDeployment.address,
            lendingPoolManagerDeployment.address,
            systemVariablesDeployment.address,
        ]),
    );

    const ksuLockBonusDeployment = await deployTransparentProxy(
        'KSULockBonus',
        deployOptions(deployer, []),
    );

    // clearing

    const acceptedRequestsCalculationDeployment = await deployTransparentProxy(
        'AcceptedRequestsCalculation',
        deployOptions(admin, []),
    );

    const clearingManagerDeployment = await deployTransparentProxy(
        'ClearingManager',
        deployOptions(admin, [
            acceptedRequestsCalculationDeployment.address,
            lendingPoolManagerDeployment.address,
        ]),
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
        userManagerDeployment.address,
        clearingManagerDeployment.address,
    );
    await tx.wait(1);

    const systemVariables = SystemVariables__factory.connect(
        systemVariablesDeployment.address,
        adminSigner,
    );
    const systemVariablesSetup: SystemVariablesSetupStruct = {
        firstEpochStartTimestamp: Math.round(Date.now() / 1000) + 3600 * 24 * 3,
        clearingPeriodLength: 1,
        protocolFee: 10_00,
        loyaltyThresholds: [10_00, 30_00],
        defaultTrancheInterestChangeEpochDelay: 1,
    };
    console.info('Initializing System Variables');
    tx = await systemVariables.initialize(systemVariablesSetup);
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

//*** UTIL FUNCTIONS ***//

function deployOptions(
    deployer: string,
    constructorArgs: unknown[],
): DeployOptions {
    return {
        deterministicDeployment: false,
        from: deployer,
        args: constructorArgs,
        log: true,
    };
}

async function deployFactory(
    hre: HardhatRuntimeEnvironment,
    addressFile: ReturnType<typeof addressFileFactory>,
    deployer: Address,
    proxyAdminAdmin: Address,
) {
    const proxyAdmin = await hre.deployments.deploy(
        'ProxyAdmin',
        deployOptions(deployer, [proxyAdminAdmin]),
    );

    return {
        deployTransparentProxy: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            const implementation = await hre.deployments.deploy(name, options);

            const transparentUpgradeableProxy = await hre.deployments.deploy(
                'TransparentUpgradeableProxy',
                deployOptions(deployer, [
                    implementation.address,
                    proxyAdmin.address,
                    [],
                ]),
            );

            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(
                exportName,
                transparentUpgradeableProxy.address,
                implementation.address,
            );
            return transparentUpgradeableProxy;
        },
        deployBeacon: async (
            name: string,
            options: DeployOptions,
            exportName?: string,
        ): Promise<DeployResult> => {
            const contractImplementation = await hre.deployments.deploy(
                name,
                options,
            );
            const beaconDeployment = await hre.deployments.deploy(
                'UpgradeableBeacon',
                deployOptions(deployer, [
                    contractImplementation.address,
                    deployer,
                ]),
            );
            exportName = exportName ? exportName : name;
            addressFile.writeAddressProxy(
                exportName + '_Beacon',
                beaconDeployment.address,
                contractImplementation.address,
            );
            return beaconDeployment;
        },
    };
}

function addressFileFactory(
    deploymentPath: string,
    blockNumber: number,
    networkName: string,
) {
    fs.writeFileSync(
        deploymentPath,
        JSON.stringify({
            network: networkName,
            startBlock: blockNumber,
        }),
    );

    return {
        writeAddressProxy: (
            name: string,
            proxy: string,
            implementation: string | undefined = undefined,
        ) =>
            writeAddressProxy(
                deploymentPath,
                blockNumber,
                name,
                proxy,
                implementation,
            ),
    };
}

function writeAddressProxy(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    proxy: string,
    implementation: string | undefined = undefined,
) {
    if (implementation) {
        _writeAddress(deploymentPath, blockNumber, name, implementation, proxy);
    } else {
        throw new Error(`Implementation address for ${name} is undefined`);
    }
}

function _writeAddress(
    deploymentPath: string,
    blockNumber: number,
    name: string,
    implementation: string,
    proxy: string | undefined = undefined,
) {
    const addresses = JSON.parse(fs.readFileSync(deploymentPath).toString());

    if (!proxy) {
        addresses[name] = {
            address: implementation,
            startBlock: blockNumber,
        };
    } else {
        addresses[name] = {
            address: proxy,
            implementation: implementation,
            startBlock: blockNumber,
        };
    }

    fs.writeFileSync(deploymentPath, JSON.stringify(addresses, null, 4));
}
