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

    // Apxium holds BOTH the "pool admin" and "pool manager" Safes on every chain they
    // operate (XDC, Plume, Base), so the split is organisational, not a trust boundary.
    // Any pool role held by either Apxium Safe (or the Kasu multisig) is valid.
    const candidates = [
        { address: poolAdminMultisig, label: 'pool admin multisig' },
        { address: poolManagerMultisig, label: 'pool manager multisig' },
        { address: kasuMultisig || '', label: 'Kasu multisig' },
    ].filter((c) => c.address);

    const roleChecks: { role: string; hash: string }[] = [
        { role: 'ROLE_POOL_ADMIN', hash: ROLE_POOL_ADMIN },
        { role: 'ROLE_POOL_CLEARING_MANAGER', hash: ROLE_POOL_CLEARING_MANAGER },
        { role: 'ROLE_POOL_MANAGER', hash: ROLE_POOL_MANAGER },
        { role: 'ROLE_POOL_FUNDS_MANAGER', hash: ROLE_POOL_FUNDS_MANAGER },
    ];

    for (const { role, hash } of roleChecks) {
        if (candidates.length === 0) break;
        const { passed, holder } = await checkPoolRole(
            kasuController, poolAddress, hash, candidates,
        );
        results.push({
            poolAddress,
            role,
            passed,
            message: passed ? `${holder} has ${role}` : `No expected address has ${role}`,
        });
    }

    return results;
}
