/**
 * Phase 3: Finalize - Revoke admin access and transfer ownership
 *
 * This script:
 * - Revokes ROLE_KASU_ADMIN from deployer/admin
 * - Transfers ProxyAdmin ownership to Kasu multisig
 * - Transfers Beacon ownership to Kasu multisig
 *
 * ⚠️  WARNING: After running this, you will lose admin control!
 * Make sure everything is configured correctly before running.
 *
 * Prerequisites:
 * - deploy_1.ts and deploy_2.ts must have been run first
 * - Smoke tests should pass
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/deploy_3.ts
 */

import { KasuController__factory } from '../typechain-types';
import { ContractTransactionResponse } from 'ethers';
import { getDeploymentFilePath } from './_utils/deploymentFileFactory';
import hre from 'hardhat';
import { getAccounts } from './_modules/getAccounts';
import { getChainConfig } from './_config/chains';
import fs from 'fs';

// Role hashes for access control
const ROLE_KASU_ADMIN = '0x0000000000000000000000000000000000000000000000000000000000000000';

// Contracts with TransparentUpgradeableProxy (each has its own ProxyAdmin)
const PROXY_CONTRACTS = [
    'USDC',
    'KasuController',
    'KSULocking',
    'KsuPrice',
    'SystemVariables',
    'FixedTermDeposit',
    'UserLoyaltyRewards',
    'UserManager',
    'Swapper',
    'LendingPoolManager',
    'FeeManager',
    'KasuAllowList',
    'ClearingCoordinator',
    'AcceptedRequestsCalculation',
    'LendingPoolFactory',
    'KSULockBonus',
    'KasuPoolExternalTVL',
    // Full deployment only
    'KSU',
];

// Beacon contracts
const BEACON_CONTRACTS = ['LendingPool', 'PendingPool', 'LendingPoolTranche'];

async function main() {
    const networkName = hre.network.name;

    // Get chain configuration
    const chainConfig = getChainConfig(networkName);

    // Load deployment addresses
    const { filePath } = getDeploymentFilePath(networkName);
    if (!fs.existsSync(filePath)) {
        console.error(`❌ Deployment file not found: ${filePath}`);
        console.error('Run deploy_1.ts first to deploy contracts.');
        process.exit(1);
    }

    const deployedAddresses = JSON.parse(fs.readFileSync(filePath, 'utf-8'));

    // get signers
    const signers = await getAccounts(networkName);

    const deployerSigner = signers[0];
    const deployerAddress = await deployerSigner.getAddress();

    const adminSigner = signers[1];
    const adminAddress = await adminSigner.getAddress();

    console.log();
    console.log('========================================');
    console.log('PHASE 3: Finalize - Transfer Ownership');
    console.log('========================================');
    console.log();
    console.log('⚠️  WARNING: This will transfer all control to the multisig!');
    console.log();
    console.log('Network:', chainConfig.name, `(${networkName})`);
    console.log('deployer account:', deployerAddress);
    console.log('admin account:', adminAddress);
    console.log('Kasu multisig:', chainConfig.kasuMultisig || '(not configured)');
    console.log();

    // Validate multisig is configured
    if (!chainConfig.kasuMultisig) {
        console.error('❌ Kasu multisig not configured in chains.ts');
        console.error('Cannot proceed without a multisig to transfer ownership to.');
        process.exit(1);
    }

    let tx: ContractTransactionResponse;

    // ==========================================
    // Part 1: Revoke ROLE_KASU_ADMIN from admin
    // ==========================================
    console.log('--------------------------------------');
    console.log('Part 1: Revoking ROLE_KASU_ADMIN from admin...');
    console.log('--------------------------------------');

    const kasuControllerAddress = deployedAddresses.KasuController?.address;
    if (!kasuControllerAddress) {
        console.error('❌ KasuController not found in deployment');
        process.exit(1);
    }

    const kasuController = KasuController__factory.connect(
        kasuControllerAddress,
        adminSigner,
    );

    // Check if admin has ROLE_KASU_ADMIN
    const adminHasRole = await kasuController.hasRole(ROLE_KASU_ADMIN, adminAddress);
    if (!adminHasRole) {
        console.log('  Admin does not have ROLE_KASU_ADMIN - already revoked ✓');
    } else {
        // Verify multisig has ROLE_KASU_ADMIN before revoking from admin
        const multisigHasRole = await kasuController.hasRole(ROLE_KASU_ADMIN, chainConfig.kasuMultisig);
        if (!multisigHasRole) {
            console.error('❌ Kasu multisig does not have ROLE_KASU_ADMIN!');
            console.error('   Run deploy_2.ts first to grant roles.');
            process.exit(1);
        }

        console.log(`  Revoking ROLE_KASU_ADMIN from admin: ${adminAddress}`);
        tx = await kasuController.revokeRole(ROLE_KASU_ADMIN, adminAddress);
        await tx.wait(1);
        console.log('  Revoked ✓');
    }

    console.log();

    // ==========================================
    // Part 2: Transfer ProxyAdmin ownership
    // ==========================================
    console.log('--------------------------------------');
    console.log('Part 2: Transferring ProxyAdmin ownership...');
    console.log('--------------------------------------');

    const ProxyAdminABI = [
        'function owner() view returns (address)',
        'function transferOwnership(address newOwner)',
    ];

    let proxyAdminTransfers = 0;
    let proxyAdminSkipped = 0;

    for (const contractName of PROXY_CONTRACTS) {
        const contractData = deployedAddresses[contractName];
        if (!contractData?.address) {
            continue; // Contract not deployed (e.g., KSU in lite mode)
        }

        try {
            // Get ProxyAdmin address for this proxy
            const proxyAdminSlot = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103';
            const proxyAdminAddressRaw = await hre.ethers.provider.getStorage(
                contractData.address,
                proxyAdminSlot,
            );
            const proxyAdminAddress = '0x' + proxyAdminAddressRaw.slice(26);

            if (proxyAdminAddress === '0x0000000000000000000000000000000000000000') {
                continue;
            }

            const proxyAdmin = new hre.ethers.Contract(
                proxyAdminAddress,
                ProxyAdminABI,
                deployerSigner,
            );

            const currentOwner = await proxyAdmin.owner();

            if (currentOwner.toLowerCase() === chainConfig.kasuMultisig.toLowerCase()) {
                console.log(`  ${contractName}: Already owned by multisig ✓`);
                proxyAdminSkipped++;
            } else if (currentOwner.toLowerCase() === deployerAddress.toLowerCase()) {
                tx = await proxyAdmin.transferOwnership(chainConfig.kasuMultisig);
                await tx.wait(1);
                console.log(`  ${contractName}: Transferred to multisig ✓`);
                proxyAdminTransfers++;
            } else {
                console.log(`  ${contractName}: Owned by unknown address (${currentOwner}) - skipping`);
                proxyAdminSkipped++;
            }
        } catch (error: any) {
            console.log(`  ${contractName}: Error - ${error.message}`);
        }
    }

    console.log(`  Transferred: ${proxyAdminTransfers}, Skipped: ${proxyAdminSkipped}`);
    console.log();

    // ==========================================
    // Part 3: Transfer Beacon ownership
    // ==========================================
    console.log('--------------------------------------');
    console.log('Part 3: Transferring Beacon ownership...');
    console.log('--------------------------------------');

    const BeaconABI = [
        'function owner() view returns (address)',
        'function transferOwnership(address newOwner)',
    ];

    let beaconTransfers = 0;
    let beaconSkipped = 0;

    for (const contractName of BEACON_CONTRACTS) {
        const contractData = deployedAddresses[contractName];
        if (!contractData?.address) {
            continue;
        }

        try {
            const beacon = new hre.ethers.Contract(
                contractData.address,
                BeaconABI,
                deployerSigner,
            );

            const currentOwner = await beacon.owner();

            if (currentOwner.toLowerCase() === chainConfig.kasuMultisig.toLowerCase()) {
                console.log(`  ${contractName}: Already owned by multisig ✓`);
                beaconSkipped++;
            } else if (currentOwner.toLowerCase() === deployerAddress.toLowerCase()) {
                tx = await beacon.transferOwnership(chainConfig.kasuMultisig);
                await tx.wait(1);
                console.log(`  ${contractName}: Transferred to multisig ✓`);
                beaconTransfers++;
            } else {
                console.log(`  ${contractName}: Owned by unknown address (${currentOwner}) - skipping`);
                beaconSkipped++;
            }
        } catch (error: any) {
            console.log(`  ${contractName}: Error - ${error.message}`);
        }
    }

    console.log(`  Transferred: ${beaconTransfers}, Skipped: ${beaconSkipped}`);
    console.log();

    // ==========================================
    // Summary
    // ==========================================
    console.log('========================================');
    console.log('PHASE 3 COMPLETE - DEPLOYMENT FINALIZED');
    console.log('========================================');
    console.log();
    console.log('Summary:');
    console.log(`  ROLE_KASU_ADMIN revoked from admin: ${adminHasRole ? 'Yes' : 'Already done'}`);
    console.log(`  ProxyAdmin ownership transfers: ${proxyAdminTransfers}`);
    console.log(`  Beacon ownership transfers: ${beaconTransfers}`);
    console.log();
    console.log('All control has been transferred to:', chainConfig.kasuMultisig);
    console.log();
    console.log('Final verification:');
    console.log('  npx hardhat --network ' + networkName + ' run scripts/smokeTests/validateDeploymentComplete.ts');
    console.log();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
