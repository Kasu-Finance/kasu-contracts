import hre from 'hardhat';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';
import { getChainConfig } from '../_config/chains';
import { UPGRADE_LISTS, Deps, UpgradeSpec } from './upgrade2026_04Spec';

/**
 * Verifies the April 2026 upgrade implementations on the block explorer.
 *
 * Safe to run any time after implementations are deployed — verification just publishes
 * the source to the explorer and doesn't touch on-chain state. Does NOT require the
 * Safe batch to have executed yet.
 *
 * Reads the manifest written by generateUpgrade2026_04.ts to get the new impl addresses,
 * re-derives constructor args from the shared spec + current addresses.json, and calls
 * hardhat verify for each one.
 *
 * Usage:
 *   npx hardhat --network xdc-usdc run scripts/upgrade/verifyUpgrade2026_04.ts
 *   npx hardhat --network xdc      run scripts/upgrade/verifyUpgrade2026_04.ts
 */

type ImplManifestEntry = {
    name: string;
    contractName: string;
    kind: 'proxy' | 'beacon';
    proxyOrBeacon: string;
    adminOrOwner: string;
    oldImpl: string;
    newImpl: string;
};

async function verifyOne(
    address: string,
    args: unknown[],
    sourcePath: string,
): Promise<{ ok: boolean; reason?: string }> {
    try {
        await hre.run('verify:verify', {
            address,
            constructorArguments: args,
            contract: sourcePath,
        });
        return { ok: true };
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        if (msg.includes('Already Verified')) {
            return { ok: true, reason: 'already verified' };
        }
        // Known Etherscan V2 + hardhat-verify 2.x quirk: submission succeeds but the
        // subsequent status check fails with "Missing chainid parameter". Treat as
        // likely-success and let the caller double-check via the explorer API.
        if (msg.includes('Missing chainid parameter')) {
            return { ok: true, reason: 'submitted (V2 status-check quirk — confirm via explorer)' };
        }
        return { ok: false, reason: msg.split('\n')[0] };
    }
}

async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);
    const specs = UPGRADE_LISTS[networkName];
    if (!specs) {
        throw new Error(
            `No April 2026 upgrade spec for '${networkName}'. Supported: ${Object.keys(UPGRADE_LISTS).join(', ')}`,
        );
    }

    dotenv.config({ path: path.join(__dirname, '..', '_env', '.env') });
    dotenv.config({ path: path.join(__dirname, '..', '_env', `.${networkName}.env`) });

    const manifestPath = `scripts/multisig/${networkName}-upgrade-2026-04-implementations.json`;
    if (!fs.existsSync(manifestPath)) {
        throw new Error(
            `Manifest not found: ${manifestPath}. Run generateUpgrade2026_04.ts first.`,
        );
    }
    const manifest: ImplManifestEntry[] = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

    const addresses = JSON.parse(
        fs.readFileSync(`.openzeppelin/${networkName}-addresses.json`, 'utf8'),
    );
    const deps: Deps = { addresses, chainConfig };

    console.log(`\n=== April 2026 impl verification — ${networkName} ===`);
    console.log(`Chain: ${chainConfig.name} (chainId ${chainConfig.chainId})`);
    console.log(`Manifest: ${manifestPath}`);
    console.log(`Impls to verify: ${manifest.length}`);
    console.log('');

    const results: Array<{ name: string; address: string; ok: boolean; reason?: string }> = [];

    for (let i = 0; i < manifest.length; i++) {
        const entry = manifest[i];
        const spec: UpgradeSpec | undefined = specs.find((s) => s.name === entry.name);
        if (!spec) {
            console.log(`[${i + 1}/${manifest.length}] SKIP ${entry.name}: no spec entry`);
            results.push({ name: entry.name, address: entry.newImpl, ok: false, reason: 'no spec' });
            continue;
        }
        const args = spec.constructorArgs(deps);
        console.log(`[${i + 1}/${manifest.length}] Verifying ${entry.contractName} @ ${entry.newImpl}`);
        if (args.length > 0) {
            console.log(`  args: ${JSON.stringify(args)}`);
        }
        const result = await verifyOne(entry.newImpl, args, spec.sourcePath);
        if (result.ok) {
            console.log(`  ✓ ${result.reason || 'verified'}`);
        } else {
            console.log(`  ✗ ${result.reason}`);
        }
        results.push({ name: entry.name, address: entry.newImpl, ...result });
        console.log('');
    }

    console.log('=== summary ===');
    const ok = results.filter((r) => r.ok).length;
    const failed = results.filter((r) => !r.ok);
    console.log(`${ok}/${results.length} verified (or submission accepted)`);
    if (failed.length > 0) {
        console.log('\nFailures:');
        for (const r of failed) console.log(`  ${r.name} (${r.address}): ${r.reason}`);
    }

    console.log('\nDouble-check any "submission accepted" entries via the explorer API:');
    console.log(
        `  curl -s "https://api.etherscan.io/v2/api?chainid=${chainConfig.chainId}&module=contract&action=getsourcecode&address=<ADDR>&apikey=$ETHERSCAN_API_KEY" \\`,
    );
    console.log(
        `    | python3 -c "import json,sys;d=json.load(sys.stdin);r=d['result'][0];print(r.get('ContractName','NOT VERIFIED') if d['status']=='1' and r.get('ContractName') else 'NOT VERIFIED')"`,
    );
}

main().catch((e) => {
    console.error(e);
    process.exitCode = 1;
});
