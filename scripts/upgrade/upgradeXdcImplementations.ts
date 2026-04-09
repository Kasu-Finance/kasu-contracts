import * as hre from 'hardhat';
import * as fs from 'fs';
import { getAccounts } from '../_modules/getAccounts';
import { getChainConfig } from '../_config/chains';

/**
 * Deploys new implementations and upgrades XDC proxies directly.
 *
 * Covers all contracts with source mismatch (validated via validateDeployment.ts):
 *   Transparent proxies:
 *     1. SystemVariables (pre-existing mismatch from Feb 11 upgrade)
 *     2. FixedTermDeposit (pre-existing mismatch)
 *     3. UserLoyaltyRewardsLite (Solidity fix)
 *     4. Swapper (pre-existing mismatch)
 *     5. LendingPoolManager (Solidity fix via DepositSwap)
 *     6. ProtocolFeeManagerLite (Solidity fix via FeeManager)
 *     7. KasuPoolExternalTVL (pre-existing mismatch)
 *
 * Deployer still owns ProxyAdmins on XDC — no Safe needed.
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/upgrade/upgradeXdcImplementations.ts
 *
 * Dry-run on Anvil fork:
 *   XDC_RPC_URL=http://127.0.0.1:8546 npx hardhat --network xdc run scripts/upgrade/upgradeXdcImplementations.ts
 */

const PROXY_ADMIN_ABI = [
    'function upgradeAndCall(address proxy, address implementation, bytes data) payable',
];

interface UpgradeResult {
    name: string;
    contractName: string;
    address: string;
    oldImplementation: string;
    newImplementation: string;
}

async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);

    if (chainConfig.chainId !== 50) {
        throw new Error(`This script is for XDC (chainId 50), got ${chainConfig.chainId}`);
    }

    console.log(`\nUpgrading ${chainConfig.name} (${networkName}) implementations...\n`);

    const deploymentFile = JSON.parse(
        fs.readFileSync(`.openzeppelin/${networkName}-addresses.json`, 'utf8')
    );

    const signers = await getAccounts(networkName);
    const deployer = signers[0];
    console.log('Deployer:', await deployer.getAddress());

    // Existing deployment addresses
    const kasuControllerAddress = deploymentFile.KasuController.address;
    const ksuPriceAddress = deploymentFile.KsuPrice.address;
    const systemVariablesAddress = deploymentFile.SystemVariables.address;
    const ksuLockingAddress = deploymentFile.KSULocking.address;
    const userLoyaltyRewardsAddress = deploymentFile.UserLoyaltyRewards.address;
    const lendingPoolManagerAddress = deploymentFile.LendingPoolManager.address;
    const fixedTermDepositAddress = deploymentFile.FixedTermDeposit.address;
    const swapperAddress = deploymentFile.Swapper.address;
    const usdcAddress = deploymentFile.USDC.address;

    // ProxyAdmin addresses (from ERC1967 admin slot via cast storage)
    const proxyAdmins: Record<string, string> = {
        SystemVariables: '0x8987070a23ff728d286f2af91d9b33f49abf3682',
        FixedTermDeposit: '0xe291a7179e4ad3d1d280798bb29ba1a7a2afa3c9',
        UserLoyaltyRewards: '0x5583d0893f45e71baeebc8bdc6042d8ab011d735',
        Swapper: '0x4bb84a14ab16e242b7db41499082471a3af8718b',
        LendingPoolManager: '0xa46bf81dbef35e631afc201042ae5399908eeaf8',
        FeeManager: '0x5a783f1c884f2418ca733dfc8f309ab56b703924',
        KasuPoolExternalTVL: '0xdefbee80c0e617a2c60dded5fd4c61bb702ef51a',
    };

    const results: UpgradeResult[] = [];

    async function upgradeProxy(
        name: string,
        contractName: string,
        constructorArgs: unknown[],
    ) {
        console.log(`\n[${results.length + 1}] Deploying ${contractName}...`);
        const Factory = await hre.ethers.getContractFactory(contractName, deployer);
        const impl = await Factory.deploy(...constructorArgs);
        await impl.waitForDeployment();
        const newImplAddr = await impl.getAddress();
        console.log(`  New implementation: ${newImplAddr}`);

        const proxyAddr = deploymentFile[name].address;
        const proxyAdminAddr = proxyAdmins[name];
        const oldImpl = deploymentFile[name].implementation;

        console.log(`  Upgrading proxy ${proxyAddr}...`);
        const proxyAdmin = new hre.ethers.Contract(proxyAdminAddr, PROXY_ADMIN_ABI, deployer);
        const tx = await proxyAdmin.upgradeAndCall(proxyAddr, newImplAddr, '0x');
        await tx.wait();
        console.log(`  Done! tx: ${tx.hash}`);

        deploymentFile[name].implementation = newImplAddr;
        results.push({ name, contractName, address: proxyAddr, oldImplementation: oldImpl, newImplementation: newImplAddr });
    }

    // 1. SystemVariables — constructor(IKsuPrice, IKasuController)
    await upgradeProxy('SystemVariables', 'SystemVariables', [ksuPriceAddress, kasuControllerAddress]);

    // 2. FixedTermDeposit — constructor(ISystemVariables)
    await upgradeProxy('FixedTermDeposit', 'FixedTermDeposit', [systemVariablesAddress]);

    // 3. UserLoyaltyRewardsLite — no constructor args
    await upgradeProxy('UserLoyaltyRewards', 'UserLoyaltyRewardsLite', []);

    // 4. Swapper — constructor(IWETH9)
    await upgradeProxy('Swapper', 'Swapper', [chainConfig.wrappedNativeAddress]);

    // 5. LendingPoolManager — constructor(IFixedTermDeposit, IERC20, IKasuController, IWETH9, ISwapper)
    await upgradeProxy('LendingPoolManager', 'LendingPoolManager', [
        fixedTermDepositAddress, usdcAddress, kasuControllerAddress,
        chainConfig.wrappedNativeAddress, swapperAddress
    ]);

    // 6. ProtocolFeeManagerLite — constructor(IERC20, ISystemVariables, IKasuController, IKSULocking, ILendingPoolManager)
    await upgradeProxy('FeeManager', 'ProtocolFeeManagerLite', [
        usdcAddress, systemVariablesAddress, kasuControllerAddress,
        ksuLockingAddress, lendingPoolManagerAddress
    ]);

    // 7. KasuPoolExternalTVL — constructor(IKasuController)
    await upgradeProxy('KasuPoolExternalTVL', 'KasuPoolExternalTVL', [kasuControllerAddress]);

    // Save updated addresses
    fs.writeFileSync(`.openzeppelin/${networkName}-addresses.json`, JSON.stringify(deploymentFile, null, 4));

    console.log('\n========================================');
    console.log(`Upgrade complete! ${results.length} contracts upgraded.`);
    console.log('========================================\n');

    for (const r of results) {
        console.log(`  ${r.name}: ${r.oldImplementation} → ${r.newImplementation}`);
    }

    console.log(`\nAddresses file updated: .openzeppelin/${networkName}-addresses.json`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
