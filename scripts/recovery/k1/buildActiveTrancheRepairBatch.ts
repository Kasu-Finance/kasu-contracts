/**
 * Builds and verifies the Safe batch for the active-tranche fix (K-1): one Safe Transaction Builder JSON per chain,
 * executed by the Kasu multisig, which owns the UserManager ProxyAdmin and the LendingPoolTranche beacon.
 *
 *   1. ProxyAdmin.upgradeAndCall(UserManager proxy, NEW_USER_MANAGER_IMPL, 0x)
 *   2. UpgradeableBeacon(LendingPoolTranche).upgradeTo(NEW_TRANCHE_IMPL)
 *   3. LendingPoolTranche.syncTrancheUser(user) for every (pool, tranche, user) with active shares
 *
 * Step 3 backfills the user manager's per-tranche records (they start empty after step 1) and re-lists holders
 * missing from a tranche users array. All steps run in one transaction, so no clearing can see a half-migrated
 * state. Run it outside the clearing window.
 *
 * Verification before writing the batch (the script fails on any mismatch):
 *   - every pool of `<network>-active-tranches.json` is a lending pool, with the same tranches;
 *   - completeness: for every tranche, the sum of `userActiveShares` over the listed users equals `totalSupply`
 *     at the current block (shares are only minted to, and burned from, users), and no listed user holds zero;
 *   - both implementations have code, are not the current ones, and carry the new function selectors;
 *   - the signer (`KASU_MULTISIG`) owns the ProxyAdmin and the beacon.
 *
 *   NEW_USER_MANAGER_IMPL=0x.. NEW_TRANCHE_IMPL=0x.. \
 *     npx hardhat --network base run scripts/recovery/k1/buildActiveTrancheRepairBatch.ts
 *
 * Re-generate the snapshot first if the completeness check fails (a new depositor since the snapshot).
 */
import fs from 'fs';
import path from 'path';
import hre from 'hardhat';
import { deploymentFileFactory } from '../../_utils/deploymentFileFactory';

const ADMIN_SLOT = '0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103';
const IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';

type Pair = { lendingPool: string; tranche: string; user: string };
type Snapshot = { network: string; snapshotBlock: number; pools: { lendingPool: string; tranches: string[] }[]; pairs: Pair[] };

function fail(message: string): never {
    throw new Error(message);
}

function selector(signature: string): string {
    return hre.ethers.id(signature).slice(2, 10);
}

async function main() {
    const { ethers } = hre;
    const network = hre.network.name;
    const provider = ethers.provider;
    const blockNumber = await provider.getBlockNumber();
    const addresses = deploymentFileFactory(network, blockNumber).getContractAddresses() as Record<string, any>;

    const userManager: string = addresses.UserManager.address;
    const trancheBeacon: string = addresses.LendingPoolTranche.address;
    const lendingPoolManager: string = addresses.LendingPoolManager.address;
    const newUserManagerImpl = process.env.NEW_USER_MANAGER_IMPL ?? fail('NEW_USER_MANAGER_IMPL not set');
    const newTrancheImpl = process.env.NEW_TRANCHE_IMPL ?? fail('NEW_TRANCHE_IMPL not set');
    const safe = process.env.KASU_MULTISIG ?? fail('KASU_MULTISIG not set');

    const snapshot: Snapshot = JSON.parse(
        fs.readFileSync(path.join(__dirname, `${network}-active-tranches.json`), 'utf8'),
    );

    // --- implementations
    for (const [impl, current, signatures] of [
        [
            newUserManagerImpl,
            ethers.getAddress('0x' + (await provider.getStorage(userManager, IMPLEMENTATION_SLOT)).slice(26)),
            ['syncUserActiveTranche(address,address,address)', 'userActiveTrancheCount(address)'],
        ],
        [
            newTrancheImpl,
            await new ethers.Contract(trancheBeacon, ['function implementation() view returns (address)'], provider).implementation(),
            ['syncTrancheUser(address)', 'isTrancheUser(address)'],
        ],
    ] as [string, string, string[]][]) {
        const code = await provider.getCode(impl);
        if (code === '0x') fail(`no code at ${impl}`);
        if (impl.toLowerCase() === current.toLowerCase()) fail(`${impl} is already the live implementation`);
        for (const sig of signatures) if (!code.includes(selector(sig))) fail(`${impl} lacks ${sig}`);
    }

    // --- owners
    const proxyAdmin = ethers.getAddress('0x' + (await provider.getStorage(userManager, ADMIN_SLOT)).slice(26));
    const ownable = ['function owner() view returns (address)'];
    for (const target of [proxyAdmin, trancheBeacon]) {
        const owner: string = await new ethers.Contract(target, ownable, provider).owner();
        if (owner.toLowerCase() !== safe.toLowerCase()) fail(`${target} is owned by ${owner}, not ${safe}`);
    }

    // --- completeness
    const lpm = new ethers.Contract(lendingPoolManager, ['function isLendingPool(address) view returns (bool)'], provider);
    const trancheAbi = [
        'function userActiveShares(address) view returns (uint256)',
        'function totalSupply() view returns (uint256)',
    ];
    for (const pool of snapshot.pools) {
        if (!(await lpm.isLendingPool(pool.lendingPool))) fail(`${pool.lendingPool} is not a lending pool`);
        const tranches: string[] = await new ethers.Contract(
            pool.lendingPool,
            ['function lendingPoolTranches() view returns (address[])'],
            provider,
        ).lendingPoolTranches();
        if (tranches.join() !== pool.tranches.join()) fail(`${pool.lendingPool}: tranche list changed`);
        for (const tranche of tranches) {
            const contract = new ethers.Contract(tranche, trancheAbi, provider);
            let sum = 0n;
            for (const pair of snapshot.pairs.filter((p) => p.tranche.toLowerCase() === tranche.toLowerCase())) {
                const shares: bigint = await contract.userActiveShares(pair.user);
                if (shares === 0n) fail(`${pair.user} holds nothing in ${tranche}: re-generate the snapshot`);
                sum += shares;
            }
            const totalSupply: bigint = await contract.totalSupply();
            if (sum !== totalSupply) fail(`${tranche}: listed shares ${sum} != totalSupply ${totalSupply}`);
        }
    }
    console.log(`complete: ${snapshot.pairs.length} pairs over ${snapshot.pools.length} pools at block ${blockNumber}`);

    // --- batch
    const tx = (to: string, signature: string, args: unknown[]) => ({
        to,
        value: '0',
        data: new ethers.Interface([`function ${signature}`]).encodeFunctionData(signature.split('(')[0], args),
        contractMethod: null,
        contractInputsValues: null,
    });
    const transactions = [
        tx(proxyAdmin, 'upgradeAndCall(address,address,bytes)', [userManager, newUserManagerImpl, '0x']),
        tx(trancheBeacon, 'upgradeTo(address)', [newTrancheImpl]),
        ...snapshot.pairs.map((p) => tx(p.tranche, 'syncTrancheUser(address)', [p.user])),
    ];
    const batch = {
        version: '1.0',
        chainId: (await provider.getNetwork()).chainId.toString(),
        createdAt: Date.now(),
        meta: {
            name: `${network}: active-tranche fix (K-1) upgrade + backfill`,
            description:
                `Upgrade UserManager to ${newUserManagerImpl} and the LendingPoolTranche beacon to ${newTrancheImpl}, ` +
                `then syncTrancheUser for all ${snapshot.pairs.length} holders (verified complete at block ${blockNumber}). ` +
                'One transaction, outside the clearing window.',
            createdFromSafeAddress: safe,
        },
        transactions,
    };
    const out = path.join(__dirname, `${network}-active-tranche-repair.safe-batch.json`);
    fs.writeFileSync(out, JSON.stringify(batch, null, 2));
    console.log(`wrote ${out} (${transactions.length} transactions)`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
