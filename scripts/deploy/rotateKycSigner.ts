import hre from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';

/**
 * Prepares the KYC signer rotation. **Sends no transaction.**
 *
 * `KasuAllowList.setNexeraIDSigner` is `onlyAdmin`, so the rotation is executed
 * by the Safe holding ROLE_KASU_ADMIN, not by a deployer key. This script does
 * the read-only half: it reports what the allow list currently verifies against,
 * checks the target `KasuKycSigner` is real, and writes two Safe Transaction
 * Builder batches — the rotation and its rollback — under
 * `scripts/deploy/safe-batches/`.
 *
 * Ordering matters: every frontend must already be signing against the backend
 * signer service before the rotation lands, because rotation takes effect on the
 * next signature verified. See README-kyc-signer.md.
 *
 * Usage:
 *   npx hardhat --network base      run scripts/deploy/rotateKycSigner.ts
 *   npx hardhat --network xdc       run scripts/deploy/rotateKycSigner.ts
 *   npx hardhat --network xdc-usdc  run scripts/deploy/rotateKycSigner.ts
 *   npx hardhat --network plume     run scripts/deploy/rotateKycSigner.ts
 *
 * Environment:
 *   KYC_SIGNER_ADDRESS        Target KasuKycSigner. Defaults to the KasuKycSigner
 *                             entry in .openzeppelin/<network>-addresses.json —
 *                             useful right after a deploy that was run without
 *                             DEPLOY_WRITE_ADDRESSES=true.
 *   ROLLBACK_SIGNER_ADDRESS   Rollback target. Defaults to whatever the allow list
 *                             verifies against right now, falling back to
 *                             COMPILOT_NEXERA_ID_SIGNER.
 *   KASU_ADMIN_SAFE           Optional. When set, the script live-checks that this
 *                             address actually holds ROLE_KASU_ADMIN, i.e. that it
 *                             can execute the batch.
 */

/**
 * Compilot's `NexeraIDSignerManager` — what sat in the signer slot before the
 * Didit migration, and therefore the rollback target.
 */
const COMPILOT_NEXERA_ID_SIGNER = '0x29A75f22AC9A7303Abb86ce521Bb44C4C69028A0';

const ALLOW_LIST_ENTRY_NAME = 'KasuAllowList';
const CONTROLLER_ENTRY_NAME = 'KasuController';
const KYC_SIGNER_ENTRY_NAME = 'KasuKycSigner';

/** ROLE_KASU_ADMIN — equals OpenZeppelin's DEFAULT_ADMIN_ROLE. See src/shared/access/Roles.sol. */
const ROLE_KASU_ADMIN = '0x0000000000000000000000000000000000000000000000000000000000000000';

const BATCH_OUTPUT_DIR = path.join(__dirname, 'safe-batches');

/** Safe Transaction Builder ABI fragment for `KasuAllowList.setNexeraIDSigner(address)`. */
const SET_NEXERA_ID_SIGNER_ABI = {
    inputs: [{ internalType: 'address', name: 'signer_', type: 'address' }],
    name: 'setNexeraIDSigner',
    payable: false,
};

type AddressEntry = { address?: string };

/**
 * Reads `<name>.address` out of `.openzeppelin/<network>-addresses.json`.
 * Returns undefined when the file or the entry is missing.
 */
function readDeployedAddress(networkName: string, name: string): string | undefined {
    const { filePath } = getDeploymentFilePath(networkName);
    if (!fs.existsSync(filePath)) {
        return undefined;
    }

    const addresses = JSON.parse(fs.readFileSync(filePath, 'utf8')) as Record<string, AddressEntry>;
    const entry = addresses[name];
    if (!entry || !entry.address) {
        return undefined;
    }

    return entry.address;
}

function buildBatch(params: {
    chainId: number;
    name: string;
    description: string;
    allowList: string;
    signer: string;
}) {
    return {
        version: '1.0',
        chainId: String(params.chainId),
        createdAt: Date.now(),
        meta: {
            name: params.name,
            description: params.description,
            txBuilderVersion: '1.16.5',
        },
        transactions: [
            {
                to: params.allowList,
                value: '0',
                data: null,
                contractMethod: SET_NEXERA_ID_SIGNER_ABI,
                contractInputsValues: { signer_: params.signer },
            },
        ],
    };
}

async function main() {
    const networkName = hre.network.name;
    const { filePath: addressesPath } = getDeploymentFilePath(networkName);
    const relativeAddressesPath = path.relative(process.cwd(), addressesPath);

    console.log(`\n=== Prepare KYC signer rotation — ${networkName} ===`);
    console.log('This script sends no transaction. It only reads and writes Safe batch JSON.\n');

    // --- Allow list ------------------------------------------------------------
    const allowListAddress = readDeployedAddress(networkName, ALLOW_LIST_ENTRY_NAME);
    if (!allowListAddress) {
        throw new Error(
            `No ${ALLOW_LIST_ENTRY_NAME} address for network '${networkName}' in ${relativeAddressesPath}. ` +
                `There is nothing to rotate.`,
        );
    }
    const allowList = hre.ethers.getAddress(allowListAddress);

    // --- Target signer ---------------------------------------------------------
    const rawTarget = process.env.KYC_SIGNER_ADDRESS ?? readDeployedAddress(networkName, KYC_SIGNER_ENTRY_NAME);
    if (!rawTarget) {
        throw new Error(
            `No ${KYC_SIGNER_ENTRY_NAME} address for network '${networkName}'. Deploy it first with ` +
                `scripts/deploy/deployKycSigner.ts, then either re-run that script with DEPLOY_WRITE_ADDRESSES=true ` +
                `or pass KYC_SIGNER_ADDRESS=0x... to this one.`,
        );
    }
    if (!hre.ethers.isAddress(rawTarget)) {
        throw new Error(`KYC_SIGNER_ADDRESS is not a valid address: ${rawTarget}`);
    }
    const kycSigner = hre.ethers.getAddress(rawTarget);

    // --- Chain ID --------------------------------------------------------------
    // The batch chainId comes from hardhat.config.ts (authoritative per network
    // name — xdc and xdc-usdc are both chain 50), cross-checked against whatever
    // the RPC reports so an Anvil fork on the wrong --chain-id is caught here
    // rather than in the Safe UI.
    const configuredChainId = hre.network.config.chainId;
    if (configuredChainId === undefined) {
        throw new Error(`Network '${networkName}' has no chainId in hardhat.config.ts.`);
    }
    const liveChainId = Number((await hre.ethers.provider.getNetwork()).chainId);
    if (liveChainId !== configuredChainId) {
        console.log(
            `WARNING: RPC reports chain ${liveChainId} but hardhat.config.ts says ${configuredChainId} for ` +
                `'${networkName}'. Looks like a fork dry-run — the batch will carry ${configuredChainId}. ` +
                `Regenerate against the real RPC before uploading anything to a Safe.\n`,
        );
    }

    console.log(`Chain ID:      ${configuredChainId}${liveChainId !== configuredChainId ? ` (RPC: ${liveChainId})` : ''}`);
    console.log(`Allow list:    ${allowList}   [from ${relativeAddressesPath}]`);

    // --- Live reads ------------------------------------------------------------
    const allowListContract = new hre.ethers.Contract(
        allowList,
        ['function txAuthDataSignerAddress() view returns (address)'],
        hre.ethers.provider,
    );
    const currentSignerRaw: string = await allowListContract.txAuthDataSignerAddress();
    const currentSigner = hre.ethers.getAddress(currentSignerRaw);

    console.log(`Current signer: ${currentSigner}   [live read: txAuthDataSignerAddress()]`);
    console.log(`Target signer:  ${kycSigner}   [KasuKycSigner]`);

    if (currentSigner === kycSigner) {
        console.log('\nNOTE: the allow list already points at this KasuKycSigner. The rotation batch is a no-op.');
    }
    if (currentSigner === hre.ethers.getAddress(COMPILOT_NEXERA_ID_SIGNER)) {
        console.log('       (current signer is the Compilot NexeraIDSignerManager — pre-rotation state, as expected)');
    }

    // --- Sanity-check the target ----------------------------------------------
    const targetCode = await hre.ethers.provider.getCode(kycSigner);
    if (targetCode === '0x') {
        throw new Error(
            `Target ${kycSigner} has no bytecode on network '${networkName}'. Rotating the allow list to an EOA-shaped ` +
                `address would take the KYC gate down: SignatureChecker would stop taking the ERC-1271 branch.`,
        );
    }

    const kycSignerContract = new hre.ethers.Contract(
        kycSigner,
        ['function signingKey() view returns (address)'],
        hre.ethers.provider,
    );
    let targetSigningKey: string;
    try {
        targetSigningKey = hre.ethers.getAddress(await kycSignerContract.signingKey());
    } catch {
        throw new Error(
            `Target ${kycSigner} has bytecode but does not answer signingKey(). That is not a KasuKycSigner — stop here.`,
        );
    }
    console.log(`Target signingKey(): ${targetSigningKey}`);

    // --- Who executes ----------------------------------------------------------
    const controllerAddress = readDeployedAddress(networkName, CONTROLLER_ENTRY_NAME);
    console.log(`\nsetNexeraIDSigner is onlyAdmin — the executing Safe must hold ROLE_KASU_ADMIN (${ROLE_KASU_ADMIN})`);
    console.log(`on KasuController ${controllerAddress ?? '(not in addresses file)'}.`);

    const adminSafe = process.env.KASU_ADMIN_SAFE;
    if (adminSafe && controllerAddress) {
        if (!hre.ethers.isAddress(adminSafe)) {
            throw new Error(`KASU_ADMIN_SAFE is not a valid address: ${adminSafe}`);
        }
        const controllerContract = new hre.ethers.Contract(
            hre.ethers.getAddress(controllerAddress),
            ['function hasRole(bytes32 role, address account) view returns (bool)'],
            hre.ethers.provider,
        );
        const hasRole: boolean = await controllerContract.hasRole(ROLE_KASU_ADMIN, hre.ethers.getAddress(adminSafe));
        console.log(
            `  hasRole(ROLE_KASU_ADMIN, ${hre.ethers.getAddress(adminSafe)}) -> ${hasRole}` +
                (hasRole ? '  OK' : '  THIS SAFE CANNOT EXECUTE THE BATCH'),
        );
    } else {
        console.log('  Set KASU_ADMIN_SAFE=0x... to have this script live-check that the Safe can execute the batch.');
    }

    // --- Rollback target -------------------------------------------------------
    // Default to whatever is live right now, so the rollback restores the exact
    // pre-rotation state. When the live read is not usable as a rollback target —
    // the rotation already happened, or the slot reads zero — fall back to the
    // documented Compilot signer rather than emitting a batch that is a no-op or
    // that reverts on `AddressLib.checkIfZero`.
    const liveReadUsable = currentSigner !== kycSigner && currentSigner !== hre.ethers.ZeroAddress;
    let rollbackSigner: string;
    let rollbackSource: string;
    if (process.env.ROLLBACK_SIGNER_ADDRESS) {
        if (!hre.ethers.isAddress(process.env.ROLLBACK_SIGNER_ADDRESS)) {
            throw new Error(`ROLLBACK_SIGNER_ADDRESS is not a valid address: ${process.env.ROLLBACK_SIGNER_ADDRESS}`);
        }
        rollbackSigner = hre.ethers.getAddress(process.env.ROLLBACK_SIGNER_ADDRESS);
        rollbackSource = 'ROLLBACK_SIGNER_ADDRESS override';
        if (rollbackSigner === hre.ethers.ZeroAddress) {
            throw new Error('ROLLBACK_SIGNER_ADDRESS is the zero address; setNexeraIDSigner would revert.');
        }
    } else if (liveReadUsable) {
        rollbackSigner = currentSigner;
        rollbackSource = 'current on-chain signer (pre-rotation state)';
    } else {
        rollbackSigner = hre.ethers.getAddress(COMPILOT_NEXERA_ID_SIGNER);
        rollbackSource =
            currentSigner === kycSigner
                ? 'Compilot NexeraIDSignerManager (rotation already applied, so the live read is not usable)'
                : 'Compilot NexeraIDSignerManager (allow list reads zero, so the live read is not usable)';
    }
    console.log(`\nRollback target: ${rollbackSigner}   [${rollbackSource}]`);

    // --- Calldata --------------------------------------------------------------
    // Printed so the operator can diff it against what the Safe UI decodes.
    const iface = new hre.ethers.Interface(['function setNexeraIDSigner(address signer_)']);
    const rotateCalldata = iface.encodeFunctionData('setNexeraIDSigner', [kycSigner]);
    const rollbackCalldata = iface.encodeFunctionData('setNexeraIDSigner', [rollbackSigner]);
    console.log('\n--- Calldata (verify against the Safe UI before signing) ---');
    console.log(`  rotate   -> ${allowList}`);
    console.log(`             ${rotateCalldata}`);
    console.log(`  rollback -> ${allowList}`);
    console.log(`             ${rollbackCalldata}`);

    // --- Write batches ---------------------------------------------------------
    fs.mkdirSync(BATCH_OUTPUT_DIR, { recursive: true });

    const rotateBatch = buildBatch({
        chainId: configuredChainId,
        name: `${networkName}: KYC signer rotation`,
        description: [
            `KasuAllowList.setNexeraIDSigner(${kycSigner})`,
            '',
            `Points the KYC signature check at the KasuKycSigner contract (ERC-1271), replacing`,
            `the Compilot NexeraIDSignerManager. Signing key behind the contract: ${targetSigningKey}.`,
            '',
            `  Allow list:      ${allowList}`,
            `  Signer before:   ${currentSigner}`,
            `  Signer after:    ${kycSigner}`,
            '',
            'PRECONDITION: every frontend must already be requesting KYC signatures from the backend',
            'signer service. Rotation takes effect on the next signature verified — signatures minted',
            'against the old signer stop being accepted the moment this executes. Drain the in-flight',
            'window (bounded by blockExpiration, ~300 blocks / ~10 min) before executing.',
            '',
            'Rollback: see the matching *-kyc-signer-rollback.json batch.',
        ].join('\n'),
        allowList,
        signer: kycSigner,
    });

    const rollbackBatch = buildBatch({
        chainId: configuredChainId,
        name: `${networkName}: KYC signer rotation ROLLBACK`,
        description: [
            `KasuAllowList.setNexeraIDSigner(${rollbackSigner})`,
            '',
            'ROLLBACK ONLY — undoes the matching *-kyc-signer-rotate.json batch by restoring the',
            `previous signer (${rollbackSource}).`,
            '',
            `  Allow list:      ${allowList}`,
            `  Signer restored: ${rollbackSigner}`,
            '',
            'Executing this re-breaks any signature minted against KasuKycSigner, so the frontends must',
            'be moved back onto the old signer path in the same window.',
        ].join('\n'),
        allowList,
        signer: rollbackSigner,
    });

    const rotatePath = path.join(BATCH_OUTPUT_DIR, `${networkName}-kyc-signer-rotate.json`);
    const rollbackPath = path.join(BATCH_OUTPUT_DIR, `${networkName}-kyc-signer-rollback.json`);
    fs.writeFileSync(rotatePath, `${JSON.stringify(rotateBatch, null, 2)}\n`);
    fs.writeFileSync(rollbackPath, `${JSON.stringify(rollbackBatch, null, 2)}\n`);

    console.log('\n--- Safe batches written ---');
    console.log(`  rotate:   ${path.relative(process.cwd(), rotatePath)}`);
    console.log(`  rollback: ${path.relative(process.cwd(), rollbackPath)}`);
    console.log('\nUpload the rotate batch to https://app.safe.global Transaction Builder from the Safe holding');
    console.log('ROLE_KASU_ADMIN. Do NOT execute until the frontends are on the backend signer.');
    console.log('See scripts/deploy/README-kyc-signer.md for the full ordering.\n');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
