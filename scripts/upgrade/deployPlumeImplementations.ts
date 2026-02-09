import * as hre from 'hardhat';
import * as fs from 'fs';

/**
 * Deploys new implementations for Plume contracts that need upgrading.
 *
 * After running this script:
 * 1. Note the new implementation addresses from output
 * 2. Run generatePlumeUpgradeJson.ts to create Gnosis Safe transaction batch
 */

interface DeployedImplementation {
    name: string;
    contractName: string;
    proxy: string;
    proxyAdmin: string;
    oldImplementation: string;
    newImplementation: string;
}

async function main() {
    const networkName = hre.network.name;
    if (networkName !== 'plume') {
        throw new Error('This script is only for Plume network');
    }

    console.log('Deploying new implementations for Plume...\n');

    const deploymentFile = JSON.parse(
        fs.readFileSync(`.openzeppelin/${networkName}-addresses.json`, 'utf8')
    );

    const signers = await hre.ethers.getSigners();
    if (signers.length === 0) {
        console.error('ERROR: No signers available. Please configure .plume.env with DEPLOYER_KEY');
        process.exit(1);
    }
    const deployer = signers[0];
    console.log('Deployer:', deployer.address);
    console.log('');

    // Get addresses from existing deployment
    const kasuControllerAddress = deploymentFile.KasuController.address;
    const ksuPriceAddress = deploymentFile.KsuPrice.address;
    const systemVariablesAddress = deploymentFile.SystemVariables.address;
    const ksuLockingAddress = deploymentFile.KSULocking.address;
    const userLoyaltyRewardsAddress = deploymentFile.UserLoyaltyRewards.address;
    const lendingPoolManagerAddress = deploymentFile.LendingPoolManager.address;
    const usdcAddress = deploymentFile.USDC.address;

    const deployed: DeployedImplementation[] = [];

    // ProxyAdmin addresses (from cast admin calls)
    const proxyAdmins: Record<string, string> = {
        KSULocking: '0x81395823cbaebb2594192628a0bf8683ef1dd626',
        KsuPrice: '0x99714a811a43c29206b2cdd16f4dd8d6eb1365a9',
        SystemVariables: '0x8d7a1813dc71f65f461e1d133d79ea7ff1bb9643',
        FixedTermDeposit: '0xecbee67ed5dd02d2b6db4c4e201a31d27af85191',
        UserLoyaltyRewards: '0x11337d45926ed4035416e160cd7bd7b0617bb9d6',
        UserManager: '0x0f8b9569d7e9c9e678166caf7081667bf096862c',
        FeeManager: '0xf190f9abeb7cb23843bdaccc05a42c70ba345e8c',
    };

    // 1. KSULockingLite - no constructor args (implements interface directly)
    console.log('1. Deploying KSULockingLite...');
    const KSULockingLite = await hre.ethers.getContractFactory('KSULockingLite');
    const ksuLockingLite = await KSULockingLite.deploy();
    await ksuLockingLite.waitForDeployment();
    const ksuLockingLiteAddr = await ksuLockingLite.getAddress();
    console.log('   KSULockingLite deployed at:', ksuLockingLiteAddr);
    deployed.push({
        name: 'KSULocking',
        contractName: 'KSULockingLite',
        proxy: deploymentFile.KSULocking.address,
        proxyAdmin: proxyAdmins.KSULocking,
        oldImplementation: deploymentFile.KSULocking.implementation,
        newImplementation: ksuLockingLiteAddr,
    });

    // 2. KsuPriceLite - no constructor args
    console.log('2. Deploying KsuPriceLite...');
    const KsuPriceLite = await hre.ethers.getContractFactory('KsuPriceLite');
    const ksuPriceLite = await KsuPriceLite.deploy();
    await ksuPriceLite.waitForDeployment();
    const ksuPriceLiteAddr = await ksuPriceLite.getAddress();
    console.log('   KsuPriceLite deployed at:', ksuPriceLiteAddr);
    deployed.push({
        name: 'KsuPrice',
        contractName: 'KsuPriceLite',
        proxy: deploymentFile.KsuPrice.address,
        proxyAdmin: proxyAdmins.KsuPrice,
        oldImplementation: deploymentFile.KsuPrice.implementation,
        newImplementation: ksuPriceLiteAddr,
    });

    // 3. SystemVariables - constructor(IKsuPrice ksuPrice_, IKasuController controller_)
    console.log('3. Deploying SystemVariables...');
    const SystemVariables = await hre.ethers.getContractFactory('SystemVariables');
    const systemVariables = await SystemVariables.deploy(ksuPriceAddress, kasuControllerAddress);
    await systemVariables.waitForDeployment();
    const systemVariablesAddr = await systemVariables.getAddress();
    console.log('   SystemVariables deployed at:', systemVariablesAddr);
    deployed.push({
        name: 'SystemVariables',
        contractName: 'SystemVariables',
        proxy: deploymentFile.SystemVariables.address,
        proxyAdmin: proxyAdmins.SystemVariables,
        oldImplementation: deploymentFile.SystemVariables.implementation,
        newImplementation: systemVariablesAddr,
    });

    // 4. FixedTermDeposit - constructor(ISystemVariables systemVariables_)
    console.log('4. Deploying FixedTermDeposit...');
    const FixedTermDeposit = await hre.ethers.getContractFactory('FixedTermDeposit');
    const fixedTermDeposit = await FixedTermDeposit.deploy(systemVariablesAddress);
    await fixedTermDeposit.waitForDeployment();
    const fixedTermDepositAddr = await fixedTermDeposit.getAddress();
    console.log('   FixedTermDeposit deployed at:', fixedTermDepositAddr);
    deployed.push({
        name: 'FixedTermDeposit',
        contractName: 'FixedTermDeposit',
        proxy: deploymentFile.FixedTermDeposit.address,
        proxyAdmin: proxyAdmins.FixedTermDeposit,
        oldImplementation: deploymentFile.FixedTermDeposit.implementation,
        newImplementation: fixedTermDepositAddr,
    });

    // 5. UserLoyaltyRewardsLite - no constructor args
    console.log('5. Deploying UserLoyaltyRewardsLite...');
    const UserLoyaltyRewardsLite = await hre.ethers.getContractFactory('UserLoyaltyRewardsLite');
    const userLoyaltyRewardsLite = await UserLoyaltyRewardsLite.deploy();
    await userLoyaltyRewardsLite.waitForDeployment();
    const userLoyaltyRewardsLiteAddr = await userLoyaltyRewardsLite.getAddress();
    console.log('   UserLoyaltyRewardsLite deployed at:', userLoyaltyRewardsLiteAddr);
    deployed.push({
        name: 'UserLoyaltyRewards',
        contractName: 'UserLoyaltyRewardsLite',
        proxy: deploymentFile.UserLoyaltyRewards.address,
        proxyAdmin: proxyAdmins.UserLoyaltyRewards,
        oldImplementation: deploymentFile.UserLoyaltyRewards.implementation,
        newImplementation: userLoyaltyRewardsLiteAddr,
    });

    // 6. UserManagerLite - constructor(ISystemVariables, IKSULocking, IUserLoyaltyRewards)
    console.log('6. Deploying UserManagerLite...');
    const UserManagerLite = await hre.ethers.getContractFactory('UserManagerLite');
    const userManagerLite = await UserManagerLite.deploy(
        systemVariablesAddress,
        ksuLockingAddress,
        userLoyaltyRewardsAddress
    );
    await userManagerLite.waitForDeployment();
    const userManagerLiteAddr = await userManagerLite.getAddress();
    console.log('   UserManagerLite deployed at:', userManagerLiteAddr);
    deployed.push({
        name: 'UserManager',
        contractName: 'UserManagerLite',
        proxy: deploymentFile.UserManager.address,
        proxyAdmin: proxyAdmins.UserManager,
        oldImplementation: deploymentFile.UserManager.implementation,
        newImplementation: userManagerLiteAddr,
    });

    // 7. ProtocolFeeManagerLite - constructor(address underlyingAsset_, ISystemVariables, IKasuController, IKSULocking, ILendingPoolManager)
    console.log('7. Deploying ProtocolFeeManagerLite...');
    const ProtocolFeeManagerLite = await hre.ethers.getContractFactory('ProtocolFeeManagerLite');
    const protocolFeeManagerLite = await ProtocolFeeManagerLite.deploy(
        usdcAddress,
        systemVariablesAddress,
        kasuControllerAddress,
        ksuLockingAddress,
        lendingPoolManagerAddress
    );
    await protocolFeeManagerLite.waitForDeployment();
    const protocolFeeManagerLiteAddr = await protocolFeeManagerLite.getAddress();
    console.log('   ProtocolFeeManagerLite deployed at:', protocolFeeManagerLiteAddr);
    deployed.push({
        name: 'FeeManager',
        contractName: 'ProtocolFeeManagerLite',
        proxy: deploymentFile.FeeManager.address,
        proxyAdmin: proxyAdmins.FeeManager,
        oldImplementation: deploymentFile.FeeManager.implementation,
        newImplementation: protocolFeeManagerLiteAddr,
    });

    console.log('\n========================================');
    console.log('All implementations deployed successfully!');
    console.log('========================================\n');

    // Save deployed implementations to a file for the upgrade script
    const outputPath = `scripts/multisig/plume-implementations.json`;
    fs.writeFileSync(outputPath, JSON.stringify(deployed, null, 2));
    console.log(`Saved implementation addresses to: ${outputPath}`);

    // Generate Gnosis Safe JSON
    generateGnosisSafeJson(deployed);
}

function generateGnosisSafeJson(deployed: DeployedImplementation[]) {
    // ProxyAdmin ABI for upgradeAndCall
    const upgradeAndCallAbi = {
        inputs: [
            { internalType: 'address', name: 'proxy', type: 'address' },
            { internalType: 'address', name: 'implementation', type: 'address' },
            { internalType: 'bytes', name: 'data', type: 'bytes' },
        ],
        name: 'upgradeAndCall',
        payable: false,
    };

    const transactions = deployed.map((impl) => ({
        to: impl.proxyAdmin,
        value: '0',
        data: null,
        contractMethod: upgradeAndCallAbi,
        contractInputsValues: {
            proxy: impl.proxy,
            implementation: impl.newImplementation,
            data: '0x', // No initialization data needed
        },
    }));

    // Add revoke old admin transaction
    const KASU_CONTROLLER = '0x7923837dC93d897E12696e0F4FD50b51FBacf693';
    const OLD_ADMIN = '0x0e7e0a898ddBbE859d08976dE1673c7A9F579483';
    const DEFAULT_ADMIN_ROLE = '0x0000000000000000000000000000000000000000000000000000000000000000';

    const revokeRoleAbi = {
        inputs: [
            { internalType: 'bytes32', name: 'role', type: 'bytes32' },
            { internalType: 'address', name: 'account', type: 'address' },
        ],
        name: 'revokeRole',
        payable: false,
    };

    transactions.push({
        to: KASU_CONTROLLER,
        value: '0',
        data: null,
        contractMethod: revokeRoleAbi,
        contractInputsValues: {
            role: DEFAULT_ADMIN_ROLE,
            account: OLD_ADMIN,
        },
    });

    const gnosisSafeJson = {
        version: '1.0',
        chainId: '98866',
        createdAt: Date.now(),
        meta: {
            name: 'Plume: Upgrade Contracts & Revoke Old Admin',
            description: [
                'This batch transaction:',
                '',
                '1. Upgrades 7 contracts to latest implementations:',
                ...deployed.map((d) => `   - ${d.name} (${d.contractName})`),
                '',
                '2. Revokes DEFAULT_ADMIN_ROLE from old admin:',
                `   - ${OLD_ADMIN}`,
            ].join('\n'),
            txBuilderVersion: '1.16.5',
        },
        transactions,
    };

    const outputPath = 'scripts/multisig/plume-upgrade-all.json';
    fs.writeFileSync(outputPath, JSON.stringify(gnosisSafeJson, null, 2));
    console.log(`\nGenerated Gnosis Safe transaction batch: ${outputPath}`);
    console.log(`Total transactions: ${transactions.length} (7 upgrades + 1 revoke)`);
    console.log(`\nUpload this JSON to Gnosis Safe Transaction Builder to execute.`);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
