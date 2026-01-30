/**
 * Phase 2: Grant roles to multisigs (keep admin control)
 *
 * This script:
 * - Grants ROLE_KASU_ADMIN to Kasu multisig
 * - Grants ROLE_LENDING_POOL_CREATOR to Pool Admin multisig
 * - Grants ROLE_PROTOCOL_FEE_CLAIMER to protocol fee claimer
 *
 * DOES NOT:
 * - Revoke ROLE_KASU_ADMIN from deployer/admin
 * - Transfer ProxyAdmin ownership
 * - Transfer Beacon ownership
 *
 * This allows you to verify the deployment before giving up control.
 * Run deploy_3.ts when ready to finalize.
 *
 * Prerequisites:
 * - deploy_1.ts must have been run first
 *
 * Usage:
 *   npx hardhat --network xdc run scripts/deploy_2.ts
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
const ROLE_LENDING_POOL_CREATOR = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_LENDING_POOL_CREATOR'),
);
const ROLE_PROTOCOL_FEE_CLAIMER = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_PROTOCOL_FEE_CLAIMER'),
);

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
    console.log('PHASE 2: Grant Roles to Multisigs');
    console.log('========================================');
    console.log();
    console.log('Network:', chainConfig.name, `(${networkName})`);
    console.log('deployer account:', deployerAddress);
    console.log('admin account:', adminAddress);
    console.log();
    console.log('Target multisigs:');
    console.log('  Kasu multisig:', chainConfig.kasuMultisig || '(not configured)');
    console.log('  Pool Admin multisig:', chainConfig.poolAdminMultisig || '(not configured)');
    console.log('  Protocol Fee Claimer:', chainConfig.protocolFeeClaimer || '(not configured)');
    console.log();

    let tx: ContractTransactionResponse;

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
        console.log('⚠️  Admin does not have ROLE_KASU_ADMIN');
        console.log('   Cannot grant roles without admin access.');
        process.exit(1);
    }

    console.log('--------------------------------------');
    console.log('Granting roles...');
    console.log('--------------------------------------');

    // Grant ROLE_KASU_ADMIN to multisig
    if (chainConfig.kasuMultisig && chainConfig.kasuMultisig !== '') {
        const multisigHasRole = await kasuController.hasRole(ROLE_KASU_ADMIN, chainConfig.kasuMultisig);
        if (multisigHasRole) {
            console.log(`✓ ROLE_KASU_ADMIN: Kasu multisig already has role`);
        } else {
            console.log(`✓ Granting ROLE_KASU_ADMIN to Kasu multisig: ${chainConfig.kasuMultisig}`);
            tx = await kasuController.grantRole(ROLE_KASU_ADMIN, chainConfig.kasuMultisig);
            await tx.wait(1);
        }
    } else {
        console.log('⚠️  Kasu multisig not configured - ROLE_KASU_ADMIN not granted');
    }

    // Grant ROLE_LENDING_POOL_CREATOR to Pool Admin multisig
    if (chainConfig.poolAdminMultisig && chainConfig.poolAdminMultisig !== '') {
        const poolAdminHasRole = await kasuController.hasRole(ROLE_LENDING_POOL_CREATOR, chainConfig.poolAdminMultisig);
        if (poolAdminHasRole) {
            console.log(`✓ ROLE_LENDING_POOL_CREATOR: Pool Admin multisig already has role`);
        } else {
            console.log(`✓ Granting ROLE_LENDING_POOL_CREATOR to Pool Admin multisig: ${chainConfig.poolAdminMultisig}`);
            tx = await kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, chainConfig.poolAdminMultisig);
            await tx.wait(1);
        }
    } else {
        console.log('⚠️  Pool Admin multisig not configured - ROLE_LENDING_POOL_CREATOR not granted');
    }

    // Grant ROLE_PROTOCOL_FEE_CLAIMER
    if (chainConfig.protocolFeeClaimer && chainConfig.protocolFeeClaimer !== '') {
        const feeClaimerHasRole = await kasuController.hasRole(ROLE_PROTOCOL_FEE_CLAIMER, chainConfig.protocolFeeClaimer);
        if (feeClaimerHasRole) {
            console.log(`✓ ROLE_PROTOCOL_FEE_CLAIMER: Protocol fee claimer already has role`);
        } else {
            console.log(`✓ Granting ROLE_PROTOCOL_FEE_CLAIMER to: ${chainConfig.protocolFeeClaimer}`);
            tx = await kasuController.grantRole(ROLE_PROTOCOL_FEE_CLAIMER, chainConfig.protocolFeeClaimer);
            await tx.wait(1);
        }
    } else {
        console.log('⚠️  Protocol fee claimer not configured - ROLE_PROTOCOL_FEE_CLAIMER not granted');
    }

    console.log();
    console.log('========================================');
    console.log('PHASE 2 COMPLETE');
    console.log('========================================');
    console.log();
    console.log('Roles granted. Admin still has full control.');
    console.log();
    console.log('Next steps:');
    console.log('1. Verify roles: npx hardhat --network ' + networkName + ' run scripts/smokeTests/validateDeploymentComplete.ts');
    console.log('2. When ready to finalize: npx hardhat --network ' + networkName + ' run scripts/deploy_3.ts');
    console.log();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
