import hre from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';
import { getAccounts } from '../_modules/getAccounts';
import { deploymentFileFactory, getDeploymentFilePath } from '../_utils/deploymentFileFactory';

/**
 * Deploys `KasuKycSigner` — the ERC-1271 contract that replaces Compilot's
 * `NexeraIDSignerManager` in the `KasuAllowList` signer slot.
 *
 * Deploying does NOT change any behaviour on its own. The allow list keeps
 * verifying against whatever `txAuthDataSignerAddress()` already points at until
 * a separate `setNexeraIDSigner` transaction lands — see
 * `scripts/deploy/rotateKycSigner.ts` and `README-kyc-signer.md`.
 *
 * `KasuKycSigner` is deliberately NOT behind a proxy: it holds one address of
 * state and rotation is a plain setter, so there is nothing to upgrade. If the
 * contract itself ever had to be replaced, `setNexeraIDSigner` is pointed at a
 * newly deployed one.
 *
 * Usage:
 *   # 1. Anvil dry-run against a fork (see README-kyc-signer.md for per-chain RPCs)
 *   anvil --fork-url https://rpc.primenumbers.xyz/ --chain-id 50 --port 8546
 *   XDC_RPC_URL=http://127.0.0.1:8546 \
 *     npx hardhat --network xdc run scripts/deploy/deployKycSigner.ts
 *
 *   # 2. Real run (prints instructions; does not touch the addresses file)
 *   npx hardhat --network base run scripts/deploy/deployKycSigner.ts
 *
 *   # 3. Real run that also records the address in .openzeppelin/<network>-addresses.json
 *   DEPLOY_WRITE_ADDRESSES=true \
 *     npx hardhat --network base run scripts/deploy/deployKycSigner.ts
 *
 * Environment:
 *   KYC_SIGNER_KEY_ADDRESS  Override the signing key address baked in below.
 *                           Defaults to DEFAULT_KYC_SIGNER_KEY_ADDRESS.
 *   DEPLOY_WRITE_ADDRESSES  'true' to write the deployed address into the shared
 *                           .openzeppelin addresses file. Default: false.
 */

/**
 * Address derived from the AWS KMS KYC signing key. The private key never leaves
 * KMS; this is only its public address, and it is the same on all four chains so
 * the backend signer service has one key to hold.
 *
 * Override with KYC_SIGNER_KEY_ADDRESS only for a dry-run or a key rotation that
 * has not yet been folded back into this constant.
 */
const DEFAULT_KYC_SIGNER_KEY_ADDRESS = '0xe99a7ec33cef5b09db5e7af9a9b0a648660244f6';

const ADDRESS_ENTRY_NAME = 'KasuKycSigner';
const CONTROLLER_ENTRY_NAME = 'KasuController';

/** ERC-1271 magic value — `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`. */
const ERC1271_MAGIC_VALUE = '0x1626ba7e';
const ERC1271_FAILURE_VALUE = '0x00000000';

type AddressEntry = { address?: string };

/**
 * Reads `<name>.address` out of `.openzeppelin/<network>-addresses.json`.
 * Returns undefined when the file or the entry is missing — callers decide
 * whether that is fatal.
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

async function main() {
    const networkName = hre.network.name;
    const { filePath: addressesPath } = getDeploymentFilePath(networkName);
    const relativeAddressesPath = path.relative(process.cwd(), addressesPath);

    console.log(`\n=== Deploy KasuKycSigner — ${networkName} ===\n`);

    // --- Controller resolution -------------------------------------------------
    // Resolved straight from the addresses file by network name rather than from
    // scripts/_config/chains.ts, so this script has exactly one source of truth
    // for on-chain addresses.
    const controllerAddress = readDeployedAddress(networkName, CONTROLLER_ENTRY_NAME);
    if (!controllerAddress) {
        throw new Error(
            `No ${CONTROLLER_ENTRY_NAME} address for network '${networkName}' in ${relativeAddressesPath}. ` +
                `KasuKycSigner takes the controller as a constructor argument, so there is nothing to deploy ` +
                `against. Supported networks are the ones with a populated .openzeppelin/<network>-addresses.json ` +
                `(base, xdc, xdc-usdc, plume).`,
        );
    }

    const controller = hre.ethers.getAddress(controllerAddress);

    // A controller with no bytecode means we are pointed at the wrong chain (or a
    // bare Anvil instead of a fork). Deploying here would bind the signer to an
    // address that does not exist.
    const controllerCode = await hre.ethers.provider.getCode(controller);
    if (controllerCode === '0x') {
        throw new Error(
            `${CONTROLLER_ENTRY_NAME} ${controller} has no bytecode on the chain behind network '${networkName}'. ` +
                `Point the network at the real chain, or at an Anvil fork of it — a bare Anvil will not do.`,
        );
    }

    // --- Signing key -----------------------------------------------------------
    const rawSigningKey = process.env.KYC_SIGNER_KEY_ADDRESS ?? DEFAULT_KYC_SIGNER_KEY_ADDRESS;
    if (!hre.ethers.isAddress(rawSigningKey)) {
        throw new Error(`KYC_SIGNER_KEY_ADDRESS is not a valid address: ${rawSigningKey}`);
    }
    const signingKey = hre.ethers.getAddress(rawSigningKey);
    const usingOverride = process.env.KYC_SIGNER_KEY_ADDRESS !== undefined;

    // --- Deployer --------------------------------------------------------------
    const signers = await getAccounts(networkName);
    const deployer = signers[0];
    if (!deployer) {
        throw new Error(
            `No deployer account configured for network '${networkName}'. ` +
                `Set DEPLOYER_KEY in scripts/_env/.${networkName}.env.`,
        );
    }
    const deployerAddress = await deployer.getAddress();

    const chainId = (await hre.ethers.provider.getNetwork()).chainId;
    const balance = await hre.ethers.provider.getBalance(deployerAddress);

    console.log(`Chain ID:    ${chainId}`);
    console.log(`Deployer:    ${deployerAddress} (${hre.ethers.formatEther(balance)} native)`);
    console.log(`Controller:  ${controller}   [from ${relativeAddressesPath}]`);
    console.log(`Signing key: ${signingKey}${usingOverride ? '   [KYC_SIGNER_KEY_ADDRESS override]' : '   [default]'}`);

    const existing = readDeployedAddress(networkName, ADDRESS_ENTRY_NAME);
    if (existing) {
        console.log(
            `\nNote: ${relativeAddressesPath} already records a ${ADDRESS_ENTRY_NAME} at ${existing}. ` +
                `This run deploys a NEW one; nothing points at it until setNexeraIDSigner is executed.`,
        );
    }
    console.log('');

    // --- Deploy ----------------------------------------------------------------
    const factory = await hre.ethers.getContractFactory('KasuKycSigner', deployer);
    const kycSigner = await factory.deploy(controller, signingKey);
    console.log(`Deploy tx:   ${kycSigner.deploymentTransaction()?.hash}`);
    await kycSigner.waitForDeployment();

    const kycSignerAddress = await kycSigner.getAddress();
    const receipt = await kycSigner.deploymentTransaction()?.wait();
    const deploymentBlock = receipt?.blockNumber ?? (await hre.ethers.provider.getBlockNumber());

    console.log(`\nKasuKycSigner deployed: ${kycSignerAddress}`);
    console.log(`Block:                  ${deploymentBlock}`);

    // --- Constructor args, for verification ------------------------------------
    // Keep these two together and in this order; hardhat verify needs them verbatim.
    console.log('\n--- Constructor arguments (needed to verify) ---');
    console.log(`  kasuController_: ${controller}`);
    console.log(`  signingKey_:     ${signingKey}`);
    const encodedArgs = hre.ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'address'],
        [controller, signingKey],
    );
    console.log(`  ABI-encoded:     ${encodedArgs}`);
    console.log(
        `\n  npx hardhat --network ${networkName} verify ${kycSignerAddress} ${controller} ${signingKey}`,
    );

    // --- Post-deploy read-back -------------------------------------------------
    console.log('\n--- Post-deploy checks ---');

    const readBackKey: string = await kycSigner.signingKey();
    const keyMatches = hre.ethers.getAddress(readBackKey) === signingKey;
    console.log(`  signingKey() -> ${readBackKey} ${keyMatches ? 'OK' : 'MISMATCH'}`);
    if (!keyMatches) {
        throw new Error(
            `Deployed contract reports signingKey ${readBackKey}, expected ${signingKey}. Do not rotate to this contract.`,
        );
    }

    // Sanity that the contract answers ERC-1271 at all: a well-formed signature
    // from a throwaway key must come back as bytes4(0), not a revert and
    // certainly not the magic value. The positive case cannot be exercised here
    // because the real key lives in KMS — it is covered by KasuKycSignerTest and
    // by the frontend smoke test after rotation.
    const throwaway = hre.ethers.Wallet.createRandom();
    const dummyDigest = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('kasu-kyc-signer-deploy-smoke'));
    const dummySignature = throwaway.signingKey.sign(dummyDigest).serialized;

    const magicValue: string = await kycSigner.isValidSignature(dummyDigest, dummySignature);
    console.log(`  isValidSignature(dummy) -> ${magicValue} ${magicValue === ERC1271_FAILURE_VALUE ? 'OK' : 'UNEXPECTED'}`);
    if (magicValue === ERC1271_MAGIC_VALUE) {
        throw new Error(
            `isValidSignature accepted a signature from a throwaway key (${throwaway.address}). ` +
                `Something is very wrong — do not rotate to this contract.`,
        );
    }
    if (magicValue !== ERC1271_FAILURE_VALUE) {
        throw new Error(`isValidSignature returned ${magicValue}, expected ${ERC1271_FAILURE_VALUE} or the magic value.`);
    }

    // --- Record the address ----------------------------------------------------
    // The .openzeppelin addresses files are shared state that other sessions and
    // the deploy scripts read, so writing is opt-in.
    const shouldWrite = process.env.DEPLOY_WRITE_ADDRESSES === 'true';
    console.log('');
    if (shouldWrite) {
        deploymentFileFactory(networkName, deploymentBlock).writeAddress(ADDRESS_ENTRY_NAME, kycSignerAddress);
        console.log(`Wrote ${ADDRESS_ENTRY_NAME} -> ${kycSignerAddress} into ${relativeAddressesPath}`);
    } else {
        console.log(`DEPLOY_WRITE_ADDRESSES is not 'true' — ${relativeAddressesPath} was left untouched.`);
        console.log('Record the deployment by re-running with DEPLOY_WRITE_ADDRESSES=true, or add by hand:');
        console.log(
            `\n    "${ADDRESS_ENTRY_NAME}": {\n` +
                `        "address": "${kycSignerAddress}",\n` +
                `        "startBlock": ${deploymentBlock}\n` +
                `    }\n`,
        );
    }

    console.log('Next: verify the source, then generate the Safe batch with');
    console.log(`      npx hardhat --network ${networkName} run scripts/deploy/rotateKycSigner.ts`);
    console.log('      (see scripts/deploy/README-kyc-signer.md — frontends must be on the backend signer first)\n');
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
