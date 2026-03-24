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

/**
 * Checks if any of the candidate addresses holds a given pool role.
 * Returns { passed, holder } where holder is the label of the address that has the role.
 */
async function checkPoolRole(
    kasuController: ReturnType<typeof KasuController__factory.connect>,
    poolAddress: string,
    role: string,
    candidates: { address: string; label: string }[],
): Promise<{ passed: boolean; holder: string }> {
    for (const { address, label } of candidates) {
        if (!address) continue;
        const hasRole = await kasuController.hasLendingPoolRole(poolAddress, role, address);
        if (hasRole) return { passed: true, holder: label };
    }
    return { passed: false, holder: '' };
}

export async function validatePoolSpecificRoles(
    poolAddress: string,
    poolManagerMultisig: string,
    poolAdminMultisig: string,
    kasuControllerAddress: string,
    kasuMultisig?: string,
): Promise<PoolValidationResult[]> {
    const results: PoolValidationResult[] = [];
    const kasuController = KasuController__factory.connect(
        kasuControllerAddress,
        hre.ethers.provider,
    );

    // Pool admin roles may be held by pool admin multisig or Kasu multisig
    const adminCandidates = [
        { address: poolAdminMultisig, label: 'pool admin multisig' },
        { address: kasuMultisig || '', label: 'Kasu multisig' },
    ].filter((c) => c.address);

    // Pool manager roles may be held by pool manager multisig or Kasu multisig
    const managerCandidates = [
        { address: poolManagerMultisig, label: 'pool manager multisig' },
        { address: kasuMultisig || '', label: 'Kasu multisig' },
    ].filter((c) => c.address);

    // Check ROLE_POOL_ADMIN
    if (adminCandidates.length > 0) {
        const { passed, holder } = await checkPoolRole(
            kasuController, poolAddress, ROLE_POOL_ADMIN, adminCandidates,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_ADMIN',
            passed,
            message: passed
                ? `${holder} has ROLE_POOL_ADMIN`
                : `No expected address has ROLE_POOL_ADMIN`,
        });
    }

    // Check ROLE_POOL_CLEARING_MANAGER
    if (adminCandidates.length > 0) {
        const { passed, holder } = await checkPoolRole(
            kasuController, poolAddress, ROLE_POOL_CLEARING_MANAGER, adminCandidates,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_CLEARING_MANAGER',
            passed,
            message: passed
                ? `${holder} has ROLE_POOL_CLEARING_MANAGER`
                : `No expected address has ROLE_POOL_CLEARING_MANAGER`,
        });
    }

    // Check ROLE_POOL_MANAGER
    if (managerCandidates.length > 0) {
        const { passed, holder } = await checkPoolRole(
            kasuController, poolAddress, ROLE_POOL_MANAGER, managerCandidates,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_MANAGER',
            passed,
            message: passed
                ? `${holder} has ROLE_POOL_MANAGER`
                : `No expected address has ROLE_POOL_MANAGER`,
        });
    }

    // Check ROLE_POOL_FUNDS_MANAGER
    if (managerCandidates.length > 0) {
        const { passed, holder } = await checkPoolRole(
            kasuController, poolAddress, ROLE_POOL_FUNDS_MANAGER, managerCandidates,
        );
        results.push({
            poolAddress,
            role: 'ROLE_POOL_FUNDS_MANAGER',
            passed,
            message: passed
                ? `${holder} has ROLE_POOL_FUNDS_MANAGER`
                : `No expected address has ROLE_POOL_FUNDS_MANAGER`,
        });
    }

    return results;
}
