import hre from 'hardhat';
import { KasuController__factory } from '../../../typechain-types';

export type PoolValidationResult = {
    poolAddress: string;
    role: string;
    passed: boolean;
    message: string;
};

// Pool-specific role constants
const ROLE_POOL_ADMIN = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('ROLE_POOL_ADMIN'));
const ROLE_POOL_MANAGER = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('ROLE_POOL_MANAGER'));
const ROLE_POOL_FUNDS_MANAGER = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_POOL_FUNDS_MANAGER'),
);
const ROLE_POOL_CLEARING_MANAGER = hre.ethers.keccak256(
    hre.ethers.toUtf8Bytes('ROLE_POOL_CLEARING_MANAGER'),
);

export async function validatePoolSpecificRoles(
    poolAddress: string,
    poolManagerMultisig: string,
    poolAdminMultisig: string,
    kasuControllerAddress: string,
): Promise<PoolValidationResult[]> {
    const results: PoolValidationResult[] = [];
    const kasuController = KasuController__factory.connect(
        kasuControllerAddress,
        hre.ethers.provider,
    );

    // Check pool admin multisig roles for this pool
    if (poolAdminMultisig) {
        const hasPoolAdmin = await kasuController.hasLendingPoolRole(
            poolAddress,
            ROLE_POOL_ADMIN,
            poolAdminMultisig,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_ADMIN',
            passed: hasPoolAdmin,
            message: hasPoolAdmin
                ? `Pool admin multisig has ROLE_POOL_ADMIN`
                : `Pool admin multisig does NOT have ROLE_POOL_ADMIN`,
        });

        const hasClearingRole = await kasuController.hasLendingPoolRole(
            poolAddress,
            ROLE_POOL_CLEARING_MANAGER,
            poolAdminMultisig,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_CLEARING_MANAGER',
            passed: hasClearingRole,
            message: hasClearingRole
                ? `Pool admin multisig has ROLE_POOL_CLEARING_MANAGER`
                : `Pool admin multisig does NOT have ROLE_POOL_CLEARING_MANAGER`,
        });
    } else {
        results.push({
            poolAddress,
            role: 'ROLE_POOL_ADMIN',
            passed: true,
            message: `Pool admin multisig not configured (skipping)`,
        });
    }

    // Check pool manager multisig roles for this pool
    if (poolManagerMultisig) {
        const hasManagerRole = await kasuController.hasLendingPoolRole(
            poolAddress,
            ROLE_POOL_MANAGER,
            poolManagerMultisig,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_MANAGER',
            passed: hasManagerRole,
            message: hasManagerRole
                ? `Pool manager multisig has ROLE_POOL_MANAGER`
                : `Pool manager multisig does NOT have ROLE_POOL_MANAGER`,
        });

        const hasFundsRole = await kasuController.hasLendingPoolRole(
            poolAddress,
            ROLE_POOL_FUNDS_MANAGER,
            poolManagerMultisig,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_FUNDS_MANAGER',
            passed: hasFundsRole,
            message: hasFundsRole
                ? `Pool manager multisig has ROLE_POOL_FUNDS_MANAGER`
                : `Pool manager multisig does NOT have ROLE_POOL_FUNDS_MANAGER`,
        });
    } else {
        results.push({
            poolAddress,
            role: 'ROLE_POOL_MANAGER',
            passed: true,
            message: `Pool manager multisig not configured (skipping)`,
        });
    }

    return results;
}
