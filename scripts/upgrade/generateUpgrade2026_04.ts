import hre, { upgrades } from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';
import { getAccounts } from '../_modules/getAccounts';
import { getChainConfig } from '../_config/chains';
import { POST_UPGRADE_TXS, UPGRADE_LISTS, UpgradeKind, Deps } from './upgrade2026_04Spec';

/**
 * April 2026 security upgrade — deploy new implementations + generate Safe batch JSON.
 *
 * Authoritative scope comes from `scripts/admin/validateDeployment.ts` (run after the
 * immutable-references fix on 2026-04-16). This script hard-codes the per-chain upgrade
 * list so the batch is deterministic and auditable; re-check against validateDeployment
 * before running and update this file if anything drifted.
 *
 * Usage:
 *   # Dry-run on Anvil fork first
 *   anvil --fork-url https://rpc.xdc.org --chain-id 50 --port 8546
 *   XDC_USDC_RPC_URL=http://127.0.0.1:8546 \
 *     npx hardhat --network xdc-usdc run scripts/upgrade/generateUpgrade2026_04.ts
 *
 *   # Real run
 *   npx hardhat --network xdc-usdc run scripts/upgrade/generateUpgrade2026_04.ts
 *   npx hardhat --network xdc      run scripts/upgrade/generateUpgrade2026_04.ts
 */

const PROXY_ADMIN_ABI_UPGRADE_AND_CALL = {
    inputs: [
        { internalType: 'address', name: 'proxy', type: 'address' },
        { internalType: 'address', name: 'implementation', type: 'address' },
        { internalType: 'bytes', name: 'data', type: 'bytes' },
    ],
    name: 'upgradeAndCall',
    payable: false,
};

const BEACON_ABI_UPGRADE_TO = {
    inputs: [{ internalType: 'address', name: 'newImplementation', type: 'address' }],
    name: 'upgradeTo',
    payable: false,
};

type BuiltTx = {
    to: string;
    value: string;
    data: null;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    contractMethod: any;
    contractInputsValues: Record<string, string>;
    // Narrative note (not part of Safe schema, stripped before write)
    _note?: string;
};

async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);
    const list = UPGRADE_LISTS[networkName];
    if (!list) {
        throw new Error(
            `No April 2026 upgrade list defined for network '${networkName}'. ` +
                `Supported: ${Object.keys(UPGRADE_LISTS).join(', ')}`,
        );
    }

    dotenv.config({ path: path.join(__dirname, '..', '_env', '.env') });
    dotenv.config({ path: path.join(__dirname, '..', '_env', `.${networkName}.env`) });

    const addressesPath = `.openzeppelin/${networkName}-addresses.json`;
    const addresses = JSON.parse(fs.readFileSync(addressesPath, 'utf8'));
    const deps: Deps = { addresses, chainConfig };

    const signers = await getAccounts(networkName);
    const deployer = signers[0];
    const deployerAddr = await deployer.getAddress();

    console.log(`\n=== April 2026 upgrade — ${networkName} ===`);
    console.log(`Chain: ${chainConfig.name} (chainId ${chainConfig.chainId})`);
    console.log(`Deployer: ${deployerAddr}`);
    console.log(`Upgrades planned: ${list.length}`);
    for (const u of list) console.log(`  - ${u.name.padEnd(22)} → ${u.contractName} (${u.kind})`);
    console.log('');

    // Beacon ABI for reading owner + current implementation
    const beaconReadAbi = [
        'function owner() view returns (address)',
        'function implementation() view returns (address)',
    ];

    const txs: BuiltTx[] = [];
    const deployed: Array<{
        name: string;
        contractName: string;
        kind: UpgradeKind;
        proxyOrBeacon: string;
        adminOrOwner: string;
        oldImpl: string;
        newImpl: string;
    }> = [];

    for (const spec of list) {
        const entry = addresses[spec.name];
        if (!entry) throw new Error(`No address entry for ${spec.name} in ${addressesPath}`);

        console.log(`[${deployed.length + 1}/${list.length}] Deploying ${spec.contractName}...`);
        const Factory = await hre.ethers.getContractFactory(spec.contractName, deployer);
        const args = spec.constructorArgs(deps);
        const impl = await Factory.deploy(...args);
        await impl.waitForDeployment();
        const newImplAddr = await impl.getAddress();
        console.log(`  new impl: ${newImplAddr}`);

        if (spec.kind === 'proxy') {
            const proxyAddr = entry.address;
            const oldImpl = await upgrades.erc1967.getImplementationAddress(proxyAddr);
            const adminAddr = await upgrades.erc1967.getAdminAddress(proxyAddr);
            // ProxyAdmin.owner() is the effective signer who must call upgradeAndCall.
            // In OZ v5 each proxy has its own ProxyAdmin contract, but all ProxyAdmins
            // should share the same owner (the Kasu multisig).
            const proxyAdmin = new hre.ethers.Contract(
                adminAddr,
                ['function owner() view returns (address)'],
                hre.ethers.provider,
            );
            const adminOwner: string = await proxyAdmin.owner();
            console.log(
                `  proxy=${proxyAddr} admin=${adminAddr} owner=${adminOwner} oldImpl=${oldImpl}`,
            );

            txs.push({
                to: adminAddr,
                value: '0',
                data: null,
                contractMethod: PROXY_ADMIN_ABI_UPGRADE_AND_CALL,
                contractInputsValues: {
                    proxy: proxyAddr,
                    implementation: newImplAddr,
                    data: '0x',
                },
                _note: `${spec.name} (${spec.contractName}) — upgradeAndCall via ProxyAdmin`,
            });
            deployed.push({
                name: spec.name,
                contractName: spec.contractName,
                kind: 'proxy',
                proxyOrBeacon: proxyAddr,
                adminOrOwner: adminOwner,
                oldImpl,
                newImpl: newImplAddr,
            });
        } else {
            // beacon
            const beaconAddr = entry.address; // addresses.json stores the beacon address here
            const bc = new hre.ethers.Contract(beaconAddr, beaconReadAbi, hre.ethers.provider);
            const oldImpl: string = await bc.implementation();
            const owner: string = await bc.owner();
            console.log(`  beacon=${beaconAddr} owner=${owner} oldImpl=${oldImpl}`);

            txs.push({
                to: beaconAddr,
                value: '0',
                data: null,
                contractMethod: BEACON_ABI_UPGRADE_TO,
                contractInputsValues: { newImplementation: newImplAddr },
                _note: `${spec.name} (${spec.contractName}) — upgradeTo on UpgradeableBeacon`,
            });
            deployed.push({
                name: spec.name,
                contractName: spec.contractName,
                kind: 'beacon',
                proxyOrBeacon: beaconAddr,
                adminOrOwner: owner,
                oldImpl,
                newImpl: newImplAddr,
            });
        }
        console.log('');
    }

    // Post-upgrade txs (currently only Base uses this — seeds UserLoyaltyRewards caps).
    // Appended to the Safe batch after all impl upgrades so they execute atomically.
    const postTxBuilder = POST_UPGRADE_TXS[networkName];
    if (postTxBuilder) {
        const postTxs = postTxBuilder(deps);
        console.log(`Appending ${postTxs.length} post-upgrade tx(s):`);
        for (const t of postTxs) {
            console.log(`  - ${t.contractMethod.name} → ${t.to}`);
            if (t._note) console.log(`    ${t._note}`);
            txs.push(t);
        }
        console.log('');
    }

    // Sanity check: every effective signer (ProxyAdmin.owner() for proxies, beacon.owner()
    // for beacons) must be the Kasu multisig — otherwise this batch cannot execute.
    // Post-upgrade txs target contracts directly (not ProxyAdmin); their signer is still
    // the Kasu multisig (holds ROLE_KASU_ADMIN for setRewardCaps etc.) but is not
    // derivable from the proxy/beacon owner query, so we skip them in the signer audit.
    const signers_ = new Set(deployed.map((d) => d.adminOrOwner.toLowerCase()));
    console.log('Effective signers (expect exactly 1 — the Kasu multisig):');
    for (const a of signers_) console.log(`  ${a}`);
    if (signers_.size !== 1) {
        throw new Error(
            `Expected all ProxyAdmin owners and beacon owners to be the same address (the Kasu multisig), ` +
                `but got ${signers_.size} distinct: ${[...signers_].join(', ')}. ` +
                `Investigate before uploading the Safe batch.`,
        );
    }
    const expectedSigner = chainConfig.kasuMultisig?.toLowerCase();
    const actualSigner = [...signers_][0];
    if (expectedSigner && actualSigner !== expectedSigner) {
        throw new Error(
            `Effective signer ${actualSigner} does not match chainConfig.kasuMultisig ${expectedSigner}`,
        );
    }

    // Write implementation manifest
    const manifestPath = `scripts/multisig/${networkName}-upgrade-2026-04-implementations.json`;
    fs.writeFileSync(manifestPath, JSON.stringify(deployed, null, 2));
    console.log(`\nImplementation manifest: ${manifestPath}`);

    // Build Safe batch JSON
    const cleanTxs = txs.map(({ _note: _note, ...rest }) => rest);
    const postTxs = postTxBuilder ? postTxBuilder(deps) : [];
    const batch = {
        version: '1.0',
        chainId: String(chainConfig.chainId),
        createdAt: Date.now(),
        meta: {
            name: `${chainConfig.name}: April 2026 security upgrade`,
            description: [
                'Upgrade impls for April 2026 audit fixes (M-03, M-04, M-06, M-08, FV-01).',
                `Source commit: see git HEAD when this batch was generated.`,
                '',
                'Transactions:',
                ...deployed.map(
                    (d, i) =>
                        `  ${i + 1}. ${d.name} (${d.contractName}) ${d.kind === 'proxy' ? 'upgradeAndCall' : 'upgradeTo'} — ${d.oldImpl} → ${d.newImpl}`,
                ),
                ...postTxs.map(
                    (t, i) =>
                        `  ${deployed.length + i + 1}. ${t.contractMethod.name} → ${t.to}` +
                        (t._note ? ` (${t._note.split('\n')[0]})` : ''),
                ),
            ].join('\n'),
            txBuilderVersion: '1.16.5',
        },
        transactions: cleanTxs,
    };

    const batchPath = `scripts/multisig/${networkName}-upgrade-2026-04.json`;
    fs.writeFileSync(batchPath, JSON.stringify(batch, null, 2));
    console.log(`Safe batch: ${batchPath}`);
    console.log(`Total txs: ${cleanTxs.length}`);
    console.log('\nUpload the Safe batch JSON to https://app.safe.global Transaction Builder.');
}

main().catch((e) => {
    console.error(e);
    process.exitCode = 1;
});
