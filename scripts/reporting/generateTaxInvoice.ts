import hre from 'hardhat';
import fs from 'fs';
import path from 'path';
import { getChainConfig } from '../_config/chains';
import { requireEnv } from '../_utils/env';
import {
    LendingPool__factory,
    PendingPool__factory,
    LendingPoolTranche__factory,
    SystemVariables__factory,
    FixedTermDeposit__factory,
} from '../../typechain-types';
import { getDeploymentFilePath } from '../_utils/deploymentFileFactory';
import { EventLog, Contract } from 'ethers';

// ─── Config ──────────────────────────────────────────────────────────────────

const USDC_DECIMALS = 6;
const CHUNK_SIZE = 1_000_000; // blocks per eth_getLogs query
const MONTH_NAMES = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
];

// ─── Strategy name mapping (pool address → human-readable name) ──────────────

const STRATEGY_NAMES: Record<string, string> = {
    '0x03f93c8caa9a82e000d35673ba34a4c0e6e117a2': 'Whole Ledger Funding - Professional Services Firms',
    '0xc347a9e4aec8c8d11a149d2907deb2bf23b81c6f': 'Professional Fee Funding - Accounting Firms',
    '0xc987350716fe4a7d674c3591c391d29eba26b8ce': 'Taxation Funding (Tax Pay) - Diversified Businesses',
    '0xb6deab2f712efc9df8c1e949b194bee12f9c04fe': 'Payment Finance (PayFi) - Payment Clearing Houses',
};

// Tranche name cache: tranche address → human-readable name (populated at startup from on-chain name())
const trancheNameCache = new Map<string, string>();

function getStrategyName(poolAddress: string): string {
    return STRATEGY_NAMES[poolAddress.toLowerCase()] || poolAddress;
}

// ─── Types ───────────────────────────────────────────────────────────────────

interface PoolInfo {
    lendingPool: string;
    pendingPool: string;
    tranches: string[];
}

interface DepositRecord {
    date: string;
    block: number;
    txHash: string;
    pool: string;
    strategy: string;
    tranche: string;
    trancheName: string;
    usdcAmount: string;
    sharesReceived: string;
}

interface WithdrawalRecord {
    date: string;
    block: number;
    txHash: string;
    pool: string;
    strategy: string;
    tranche: string;
    trancheName: string;
    usdcAmount: string;
    sharesBurned: string;
}

interface YieldRecord {
    epoch: number;
    epochStartDate: string;
    pool: string;
    strategy: string;
    tranche: string;
    trancheName: string;
    yieldUsdc: string;
    userShares: string;
    totalSupply: string;
}

interface BalanceRecord {
    pool: string;
    strategy: string;
    tranche: string;
    trancheName: string;
    shares: string;
    usdcValue: string;
}

interface FtdRecord {
    ftdId: number;
    pool: string;
    strategy: string;
    tranche: string;
    trancheName: string;
    lockedShares: string;
    epochLockStart: number;
    epochLockEnd: number;
    interestDiffs: { epoch: number; interestAmount: string; trancheShares: string }[];
}

interface MonthlyRecord {
    month: string;     // e.g., "December 2025"
    monthKey: string;  // e.g., "2025-12"
    deposits: string;
    withdrawals: string;
    yieldEarned: string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatUsdc(amount: bigint): string {
    const whole = amount / BigInt(10 ** USDC_DECIMALS);
    const frac = amount % BigInt(10 ** USDC_DECIMALS);
    const fracStr = frac.toString().padStart(USDC_DECIMALS, '0');
    return `${whole}.${fracStr.slice(0, 2)}`;
}

function formatShares(amount: bigint): string {
    return amount.toString();
}

function formatSignedUsdc(amount: bigint): string {
    const negative = amount < 0n;
    const abs = negative ? -amount : amount;
    const formatted = formatUsdc(abs);
    return negative ? `-${formatted}` : formatted;
}

/** Format date as DD.MM.YYYY */
function formatDate(date: Date): string {
    const d = date.getUTCDate().toString().padStart(2, '0');
    const m = (date.getUTCMonth() + 1).toString().padStart(2, '0');
    const y = date.getUTCFullYear();
    return `${d}.${m}.${y}`;
}

async function getBlockForTimestamp(
    provider: typeof hre.ethers.provider,
    targetTimestamp: number,
    lowBlock: number,
    highBlock: number,
): Promise<number> {
    while (lowBlock < highBlock) {
        const mid = Math.floor((lowBlock + highBlock) / 2);
        const block = await provider.getBlock(mid);
        if (!block) throw new Error(`Block ${mid} not found`);
        if (block.timestamp < targetTimestamp) {
            lowBlock = mid + 1;
        } else {
            highBlock = mid;
        }
    }
    return lowBlock;
}

async function queryEventsChunked(
    contract: Contract,
    filter: any,
    fromBlock: number,
    toBlock: number,
): Promise<EventLog[]> {
    const allEvents: EventLog[] = [];
    for (let start = fromBlock; start <= toBlock; start += CHUNK_SIZE) {
        const end = Math.min(start + CHUNK_SIZE - 1, toBlock);
        try {
            const events = await contract.queryFilter(filter, start, end);
            allEvents.push(...(events.filter((e) => e instanceof EventLog) as EventLog[]));
        } catch (err: any) {
            if (err.message?.includes('block range') || err.message?.includes('too many') || err.message?.includes('limit')) {
                const mid = Math.floor((start + end) / 2);
                const first = await queryEventsChunked(contract, filter, start, mid);
                const second = await queryEventsChunked(contract, filter, mid + 1, end);
                allEvents.push(...first, ...second);
            } else {
                throw err;
            }
        }
    }
    return allEvents;
}

async function blockToDate(provider: typeof hre.ethers.provider, blockNumber: number): Promise<string> {
    const block = await provider.getBlock(blockNumber);
    if (!block) return 'unknown';
    return formatDate(new Date(block.timestamp * 1000));
}

/** Parse DD.MM.YYYY → YYYY-MM month key */
function getMonthKey(dateStr: string): string {
    const parts = dateStr.split('.');
    return `${parts[2]}-${parts[1]}`;
}

/** YYYY-MM → "December 2025" */
function getMonthLabel(key: string): string {
    const [year, month] = key.split('-');
    return `${MONTH_NAMES[parseInt(month) - 1]} ${year}`;
}

/** Generate all YYYY-MM keys between two timestamps (inclusive) */
function generateAllMonthKeys(startTs: number, endTs: number): string[] {
    const keys: string[] = [];
    const start = new Date(startTs * 1000);
    const end = new Date(endTs * 1000);
    let current = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
    while (current <= end) {
        const y = current.getUTCFullYear();
        const m = (current.getUTCMonth() + 1).toString().padStart(2, '0');
        keys.push(`${y}-${m}`);
        current.setUTCMonth(current.getUTCMonth() + 1);
    }
    return keys;
}

function getTrancheIndex(tranches: string[], trancheAddr: string): number {
    return tranches.findIndex((t) => t.toLowerCase() === trancheAddr.toLowerCase());
}

function getTrancheName(tranches: string[], trancheAddr: string): string {
    return trancheNameCache.get(trancheAddr.toLowerCase()) || `Tranche ${getTrancheIndex(tranches, trancheAddr)}`;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
    const networkName = hre.network.name;
    const chainConfig = getChainConfig(networkName);
    const provider = hre.ethers.provider;

    const depositorAddress = requireEnv('DEPOSITOR_ADDRESS');
    const reportMode = (process.env.REPORT_MODE || 'annual') as 'annual' | 'monthly-summary';
    const startDateEnv = process.env.START_DATE;
    const endDateEnv = process.env.END_DATE;

    let yearStartTimestamp: number;
    let yearEndTimestamp: number;
    let taxYear: number | undefined;
    let periodLabel: string;
    let startDateIso: string;
    let endDateIso: string;

    if (startDateEnv && endDateEnv) {
        yearStartTimestamp = Math.floor(new Date(`${startDateEnv}T00:00:00Z`).getTime() / 1000);
        yearEndTimestamp = Math.floor(new Date(`${endDateEnv}T23:59:59Z`).getTime() / 1000);
        startDateIso = startDateEnv;
        endDateIso = endDateEnv;
        periodLabel = `${formatDate(new Date(yearStartTimestamp * 1000))} – ${formatDate(new Date(yearEndTimestamp * 1000))}`;
    } else {
        taxYear = parseInt(requireEnv('TAX_YEAR'));
        yearStartTimestamp = Math.floor(new Date(`${taxYear}-01-01T00:00:00Z`).getTime() / 1000);
        yearEndTimestamp = Math.floor(new Date(`${taxYear + 1}-01-01T00:00:00Z`).getTime() / 1000) - 1;
        startDateIso = `${taxYear}-01-01`;
        endDateIso = `${taxYear}-12-31`;
        periodLabel = `FY ${taxYear}`;
    }

    console.log(`\n  Tax Invoice Generator`);
    console.log(`  =====================`);
    console.log(`  Network:   ${chainConfig.name} (${networkName})`);
    console.log(`  Depositor: ${depositorAddress}`);
    console.log(`  Period:    ${periodLabel}`);
    console.log(`  Mode:      ${reportMode}`);
    console.log();

    // ── Step 1: Determine block range ────────────────────────────────────

    const currentBlock = await provider.getBlockNumber();
    const { filePath } = getDeploymentFilePath(networkName);
    const deploymentData = JSON.parse(fs.readFileSync(filePath).toString());
    const deploymentStartBlock = deploymentData.startBlock || 0;

    console.log(`  Finding block range for ${periodLabel}...`);
    const startBlock = await getBlockForTimestamp(provider, yearStartTimestamp, deploymentStartBlock, currentBlock);
    const endBlock = yearEndTimestamp >= Math.floor(Date.now() / 1000)
        ? currentBlock
        : await getBlockForTimestamp(provider, yearEndTimestamp, startBlock, currentBlock);
    console.log(`  Block range: ${startBlock} - ${endBlock} (~${(endBlock - startBlock).toLocaleString()} blocks)`);
    console.log();

    // ── Step 2: Resolve pool sub-contracts ───────────────────────────────

    const poolAddresses = chainConfig.lendingPoolAddresses;
    console.log(`  Resolving ${poolAddresses.length} lending pools...`);

    const pools: PoolInfo[] = [];
    for (const poolAddr of poolAddresses) {
        const lendingPool = LendingPool__factory.connect(poolAddr, provider);
        try {
            const info = await lendingPool.lendingPoolInfo();
            const trancheAddrs = [...info.trancheAddresses];

            // Fetch tranche names from on-chain name()
            for (const trancheAddr of trancheAddrs) {
                if (!trancheNameCache.has(trancheAddr.toLowerCase())) {
                    const tranche = LendingPoolTranche__factory.connect(trancheAddr, provider);
                    const fullName = await tranche.name();
                    // Extract short name: "... - Junior Tranche" → "Junior"
                    const match = fullName.match(/-\s*(Senior|Mezzanine|Junior)\s*Tranche/i);
                    const shortName = match ? match[1] : fullName;
                    trancheNameCache.set(trancheAddr.toLowerCase(), shortName);
                }
            }

            pools.push({
                lendingPool: poolAddr,
                pendingPool: info.pendingPool,
                tranches: trancheAddrs,
            });
            const trancheNames = trancheAddrs.map((a) => trancheNameCache.get(a.toLowerCase())).join(', ');
            console.log(`  ${getStrategyName(poolAddr)}: ${trancheAddrs.length} tranche(s) [${trancheNames}]`);
        } catch (err: any) {
            console.warn(`  Warning: Could not resolve pool ${poolAddr}: ${err.message}`);
        }
    }
    console.log();

    // ── Step 3: Get epoch info ───────────────────────────────────────────

    const systemVariables = SystemVariables__factory.connect(deploymentData.SystemVariables.address, provider);
    const currentEpoch = await systemVariables.currentEpochNumber();
    console.log(`  Current epoch: ${currentEpoch}`);

    // Find which epochs fall within the tax year
    const epochsInYear: { epoch: number; startTimestamp: number }[] = [];
    for (let e = 0; e <= Number(currentEpoch); e++) {
        const epochStart = await systemVariables.epochStartTimestamp(e);
        const ts = Number(epochStart);
        if (ts >= yearStartTimestamp && ts <= yearEndTimestamp) {
            epochsInYear.push({ epoch: e, startTimestamp: ts });
        }
        if (ts > yearEndTimestamp) break;
    }
    console.log(`  Epochs in period: ${epochsInYear.length} (epoch ${epochsInYear[0]?.epoch ?? 'N/A'} to ${epochsInYear[epochsInYear.length - 1]?.epoch ?? 'N/A'})`);
    console.log();

    // ── Step 4: Query deposit/withdrawal events ──────────────────────────

    const deposits: DepositRecord[] = [];
    const withdrawals: WithdrawalRecord[] = [];
    const cancelledDeposits: { date: string; block: number; txHash: string; pool: string; strategy: string; tranche: string; trancheName: string; type: string }[] = [];

    for (const pool of pools) {
        const pendingPool = PendingPool__factory.connect(pool.pendingPool, provider);
        const strategy = getStrategyName(pool.lendingPool);

        console.log(`  Querying events for ${strategy}...`);

        // Deposit Accepted
        const depositAcceptedFilter = pendingPool.filters.DepositRequestAccepted(depositorAddress);
        const depositAcceptedEvents = await queryEventsChunked(pendingPool as unknown as Contract, depositAcceptedFilter, startBlock, endBlock);
        console.log(`    DepositRequestAccepted: ${depositAcceptedEvents.length}`);

        for (const event of depositAcceptedEvents) {
            const dateAccepted = await blockToDate(provider, event.blockNumber);
            const trancheAddr = event.args[1] as string;

            deposits.push({
                date: dateAccepted,
                block: event.blockNumber,
                txHash: event.transactionHash,
                pool: pool.lendingPool,
                strategy,
                tranche: trancheAddr,
                trancheName: getTrancheName(pool.tranches, trancheAddr),
                usdcAmount: formatUsdc(event.args[3] as bigint),
                sharesReceived: formatShares(event.args[4] as bigint),
            });
        }

        // Withdrawal Accepted
        const withdrawalAcceptedFilter = pendingPool.filters.WithdrawalRequestAccepted(depositorAddress);
        const withdrawalAcceptedEvents = await queryEventsChunked(pendingPool as unknown as Contract, withdrawalAcceptedFilter, startBlock, endBlock);
        console.log(`    WithdrawalRequestAccepted: ${withdrawalAcceptedEvents.length}`);

        for (const event of withdrawalAcceptedEvents) {
            const date = await blockToDate(provider, event.blockNumber);
            const trancheAddr = event.args[1] as string;
            withdrawals.push({
                date,
                block: event.blockNumber,
                txHash: event.transactionHash,
                pool: pool.lendingPool,
                strategy,
                tranche: trancheAddr,
                trancheName: getTrancheName(pool.tranches, trancheAddr),
                usdcAmount: formatUsdc(event.args[4] as bigint),
                sharesBurned: formatShares(event.args[3] as bigint),
            });
        }

        // Cancelled / Rejected deposits
        const depositCancelledFilter = pendingPool.filters.DepositRequestCancelled(depositorAddress);
        const depositCancelledEvents = await queryEventsChunked(pendingPool as unknown as Contract, depositCancelledFilter, startBlock, endBlock);
        for (const event of depositCancelledEvents) {
            const date = await blockToDate(provider, event.blockNumber);
            const trancheAddr = event.args[1] as string;
            cancelledDeposits.push({
                date, block: event.blockNumber, txHash: event.transactionHash,
                pool: pool.lendingPool, strategy,
                tranche: trancheAddr, trancheName: getTrancheName(pool.tranches, trancheAddr),
                type: 'cancelled',
            });
        }

        const depositRejectedFilter = pendingPool.filters.DepositRequestRejected(depositorAddress);
        const depositRejectedEvents = await queryEventsChunked(pendingPool as unknown as Contract, depositRejectedFilter, startBlock, endBlock);
        for (const event of depositRejectedEvents) {
            const date = await blockToDate(provider, event.blockNumber);
            const trancheAddr = event.args[1] as string;
            cancelledDeposits.push({
                date, block: event.blockNumber, txHash: event.transactionHash,
                pool: pool.lendingPool, strategy,
                tranche: trancheAddr, trancheName: getTrancheName(pool.tranches, trancheAddr),
                type: 'rejected',
            });
        }

        // Immediate withdrawals (on LendingPool, not PendingPool)
        const lendingPool = LendingPool__factory.connect(pool.lendingPool, provider);
        const immediateWithdrawalFilter = lendingPool.filters.ImmediateWithdrawal(depositorAddress);
        const immediateWithdrawalEvents = await queryEventsChunked(lendingPool as unknown as Contract, immediateWithdrawalFilter, startBlock, endBlock);
        if (immediateWithdrawalEvents.length > 0) {
            console.log(`    ImmediateWithdrawal: ${immediateWithdrawalEvents.length}`);
        }
        for (const event of immediateWithdrawalEvents) {
            const date = await blockToDate(provider, event.blockNumber);
            const trancheAddr = event.args[1] as string;
            withdrawals.push({
                date,
                block: event.blockNumber,
                txHash: event.transactionHash,
                pool: pool.lendingPool,
                strategy,
                tranche: trancheAddr,
                trancheName: getTrancheName(pool.tranches, trancheAddr),
                usdcAmount: formatUsdc(event.args[3] as bigint),
                sharesBurned: formatShares(event.args[2] as bigint),
            });
        }
    }

    console.log();
    console.log(`  Total deposits: ${deposits.length}, withdrawals: ${withdrawals.length}, cancelled/rejected: ${cancelledDeposits.length}`);
    console.log();

    // ── Step 5: Query yield per epoch ────────────────────────────────────
    //
    // Scan the full block range for InterestApplied events per pool.
    // These events fire once per tranche per clearing (~52 per tranche per year).

    console.log(`  Calculating yield per epoch...`);
    const yieldRecords: YieldRecord[] = [];

    // Build epoch lookup for date formatting
    const epochDateMap = new Map<number, string>();
    for (const e of epochsInYear) {
        epochDateMap.set(e.epoch, formatDate(new Date(e.startTimestamp * 1000)));
    }

    for (const pool of pools) {
        const lendingPool = LendingPool__factory.connect(pool.lendingPool, provider);
        const strategy = getStrategyName(pool.lendingPool);
        console.log(`  Querying InterestApplied for ${strategy}...`);

        const interestFilter = lendingPool.filters.InterestApplied();
        const interestEvents = await queryEventsChunked(lendingPool as unknown as Contract, interestFilter, startBlock, endBlock);
        console.log(`    InterestApplied events found: ${interestEvents.length}`);

        let poolYieldCount = 0;

        for (const event of interestEvents) {
            const trancheAddr = event.args[0] as string;
            const epoch = Number(event.args[1] as bigint);
            const interestAmount = event.args[2] as bigint;

            if (interestAmount === 0n) continue;

            const tranche = LendingPoolTranche__factory.connect(trancheAddr, provider);
            const [userShares, totalSupply] = await Promise.all([
                tranche.userActiveShares(depositorAddress, { blockTag: event.blockNumber }),
                tranche.totalSupply({ blockTag: event.blockNumber }),
            ]);

            if (userShares === 0n || totalSupply === 0n) continue;

            const userYield = (interestAmount * userShares) / totalSupply;
            if (userYield === 0n) continue;

            yieldRecords.push({
                epoch,
                epochStartDate: epochDateMap.get(epoch) || `epoch-${epoch}`,
                pool: pool.lendingPool,
                strategy,
                tranche: trancheAddr,
                trancheName: getTrancheName(pool.tranches, trancheAddr),
                yieldUsdc: formatUsdc(userYield),
                userShares: formatShares(userShares),
                totalSupply: formatShares(totalSupply),
            });
            poolYieldCount++;
        }

        console.log(`    User yield records: ${poolYieldCount}`);
    }

    console.log(`  Total yield records: ${yieldRecords.length}`);
    console.log();

    // ── Step 6: Query FTD events ─────────────────────────────────────────

    console.log(`  Querying Fixed Term Deposit events...`);
    const ftdRecords: FtdRecord[] = [];
    const fixedTermDeposit = FixedTermDeposit__factory.connect(deploymentData.FixedTermDeposit.address, provider);

    const ftdLockedFilter = fixedTermDeposit.filters.FixedTermDepositLocked(depositorAddress);
    const ftdLockedEvents = await queryEventsChunked(fixedTermDeposit as unknown as Contract, ftdLockedFilter, startBlock, endBlock);
    console.log(`  FTD locks in period: ${ftdLockedEvents.length}`);

    for (const event of ftdLockedEvents) {
        const ftdId = Number(event.args[2] as bigint);
        const poolAddr = event.args[1] as string;
        const trancheAddr = event.args[4] as string;
        const pool = pools.find((p) => p.lendingPool.toLowerCase() === poolAddr.toLowerCase());

        ftdRecords.push({
            ftdId,
            pool: poolAddr,
            strategy: getStrategyName(poolAddr),
            tranche: trancheAddr,
            trancheName: pool ? getTrancheName(pool.tranches, trancheAddr) : trancheAddr,
            lockedShares: formatShares(event.args[5] as bigint),
            epochLockStart: Number(event.args[6] as bigint),
            epochLockEnd: Number(event.args[7] as bigint),
            interestDiffs: [],
        });
    }

    // Query FTD interest diffs per pool (user is indexed, so this is fast)
    for (const pool of pools) {
        const lendingPool = LendingPool__factory.connect(pool.lendingPool, provider);
        const ftdInterestFilter = lendingPool.filters.FixedInterestDiffApplied(depositorAddress);
        const ftdInterestEvents = await queryEventsChunked(lendingPool as unknown as Contract, ftdInterestFilter, startBlock, endBlock);

        if (ftdInterestEvents.length > 0) {
            console.log(`  FTD interest diffs for ${getStrategyName(pool.lendingPool)}: ${ftdInterestEvents.length}`);
        }

        for (const event of ftdInterestEvents) {
            const epoch = Number(event.args[2] as bigint);
            const trancheShares = event.args[3] as bigint;
            const interestAmount = event.args[4] as bigint;
            const trancheAddr = event.args[1] as string;

            const existingFtd = ftdRecords.find((f) => f.pool.toLowerCase() === pool.lendingPool.toLowerCase() && f.tranche.toLowerCase() === trancheAddr.toLowerCase());
            const diffEntry = {
                epoch,
                interestAmount: formatSignedUsdc(interestAmount),
                trancheShares: trancheShares.toString(),
            };

            if (existingFtd) {
                existingFtd.interestDiffs.push(diffEntry);
            } else {
                ftdRecords.push({
                    ftdId: -1,
                    pool: pool.lendingPool,
                    strategy: getStrategyName(pool.lendingPool),
                    tranche: trancheAddr,
                    trancheName: getTrancheName(pool.tranches, trancheAddr),
                    lockedShares: '0',
                    epochLockStart: 0,
                    epochLockEnd: 0,
                    interestDiffs: [diffEntry],
                });
            }
        }
    }

    // ── Step 7: Opening and closing balances ─────────────────────────────

    console.log(`  Computing opening and closing balances...`);
    const openingBalances: BalanceRecord[] = [];
    const closingBalances: BalanceRecord[] = [];

    for (const pool of pools) {
        const strategy = getStrategyName(pool.lendingPool);

        for (const trancheAddr of pool.tranches) {
            const tranche = LendingPoolTranche__factory.connect(trancheAddr, provider);
            const trancheName = getTrancheName(pool.tranches, trancheAddr);

            try {
                const openShares = await tranche.userActiveShares(depositorAddress, { blockTag: startBlock });
                if (openShares > 0n) {
                    const openValue = await tranche.convertToAssets(openShares, { blockTag: startBlock });
                    openingBalances.push({ pool: pool.lendingPool, strategy, tranche: trancheAddr, trancheName, shares: formatShares(openShares), usdcValue: formatUsdc(openValue) });
                }
            } catch {
                // Contract may not have existed at startBlock
            }

            try {
                const closeShares = await tranche.userActiveShares(depositorAddress, { blockTag: endBlock });
                if (closeShares > 0n) {
                    const closeValue = await tranche.convertToAssets(closeShares, { blockTag: endBlock });
                    closingBalances.push({ pool: pool.lendingPool, strategy, tranche: trancheAddr, trancheName, shares: formatShares(closeShares), usdcValue: formatUsdc(closeValue) });
                }
            } catch {
                // Contract may not have existed at endBlock
            }
        }
    }

    console.log(`  Opening positions: ${openingBalances.length}, Closing positions: ${closingBalances.length}`);
    console.log();

    // ── Step 8: Reconcile yield with balance sheet ─────────────────────
    //
    // The exact total yield is derived from on-chain balances:
    //   yield = closingBalance - openingBalance - deposits + withdrawals
    // We then proportionally adjust per-epoch records so they sum exactly.

    const totalDeposited = deposits.reduce((sum, d) => sum + parseFloat(d.usdcAmount), 0);
    const totalWithdrawn = withdrawals.reduce((sum, w) => sum + parseFloat(w.usdcAmount), 0);
    const openingBalance = openingBalances.reduce((sum, b) => sum + parseFloat(b.usdcValue), 0);
    const closingBalance = closingBalances.reduce((sum, b) => sum + parseFloat(b.usdcValue), 0);

    // Exact yield from balance sheet
    const exactTotalYield = closingBalance - openingBalance - totalDeposited + totalWithdrawn;

    // Raw yield from epoch-by-epoch calculation
    const rawTotalYield = yieldRecords.reduce((sum, y) => sum + parseFloat(y.yieldUsdc), 0);
    const totalFtdInterest = ftdRecords.reduce(
        (sum, f) => sum + f.interestDiffs.reduce((s, d) => s + parseFloat(d.interestAmount), 0),
        0,
    );
    const rawTotal = rawTotalYield + totalFtdInterest;

    // Proportionally adjust yield records so they sum to exactTotalYield
    if (rawTotal > 0 && Math.abs(exactTotalYield - rawTotal) > 0.001) {
        const adjustmentFactor = (exactTotalYield - totalFtdInterest) / rawTotalYield;
        console.log(`  Reconciling yield: raw $${rawTotal.toFixed(2)} -> exact $${exactTotalYield.toFixed(2)} (adjustment: ${((adjustmentFactor - 1) * 100).toFixed(4)}%)`);

        let runningSum = 0;
        for (let i = 0; i < yieldRecords.length; i++) {
            if (i === yieldRecords.length - 1) {
                // Last record absorbs any remaining rounding to ensure exact sum
                const target = exactTotalYield - totalFtdInterest;
                yieldRecords[i].yieldUsdc = (target - runningSum).toFixed(2);
            } else {
                const adjusted = parseFloat(yieldRecords[i].yieldUsdc) * adjustmentFactor;
                yieldRecords[i].yieldUsdc = adjusted.toFixed(2);
                runningSum += parseFloat(yieldRecords[i].yieldUsdc);
            }
        }
    }

    const totalYield = yieldRecords.reduce((sum, y) => sum + parseFloat(y.yieldUsdc), 0);

    // ── Step 9: Monthly breakdown ───────────────────────────────────────

    const allMonthKeys = generateAllMonthKeys(yearStartTimestamp, yearEndTimestamp);
    const monthBuckets = new Map<string, { deposits: number; withdrawals: number; yield: number }>();
    for (const key of allMonthKeys) {
        monthBuckets.set(key, { deposits: 0, withdrawals: 0, yield: 0 });
    }

    for (const d of deposits) {
        const key = getMonthKey(d.date);
        const bucket = monthBuckets.get(key);
        if (bucket) bucket.deposits += parseFloat(d.usdcAmount);
    }

    for (const w of withdrawals) {
        const key = getMonthKey(w.date);
        const bucket = monthBuckets.get(key);
        if (bucket) bucket.withdrawals += parseFloat(w.usdcAmount);
    }

    for (const y of yieldRecords) {
        const key = getMonthKey(y.epochStartDate);
        const bucket = monthBuckets.get(key);
        if (bucket) bucket.yield += parseFloat(y.yieldUsdc);
    }

    for (const f of ftdRecords) {
        for (const diff of f.interestDiffs) {
            const epochDate = epochDateMap.get(diff.epoch);
            if (epochDate) {
                const key = getMonthKey(epochDate);
                const bucket = monthBuckets.get(key);
                if (bucket) bucket.yield += parseFloat(diff.interestAmount);
            }
        }
    }

    const monthlyBreakdown: MonthlyRecord[] = allMonthKeys.map((key) => {
        const data = monthBuckets.get(key)!;
        return {
            month: getMonthLabel(key),
            monthKey: key,
            deposits: data.deposits.toFixed(2),
            withdrawals: data.withdrawals.toFixed(2),
            yieldEarned: data.yield.toFixed(2),
        };
    });

    // ── Step 10: Build output ────────────────────────────────────────────

    const fileSlug = taxYear != null
        ? `${depositorAddress.toLowerCase()}-${taxYear}`
        : `${depositorAddress.toLowerCase()}-${startDateIso}-to-${endDateIso}`;

    const invoice = {
        reportMode,
        depositor: depositorAddress,
        chain: chainConfig.name,
        chainId: chainConfig.chainId,
        taxYear: taxYear ?? null,
        startDate: startDateIso,
        endDate: endDateIso,
        periodLabel,
        generatedAt: new Date().toISOString(),
        currency: 'USDC',
        blockRange: { startBlock, endBlock },
        summary: {
            totalDeposited: totalDeposited.toFixed(2),
            totalWithdrawn: totalWithdrawn.toFixed(2),
            totalYieldEarned: (totalYield + totalFtdInterest).toFixed(2),
            openingBalance: openingBalance.toFixed(2),
            closingBalance: closingBalance.toFixed(2),
        },
        monthlyBreakdown,
        openingBalances,
        closingBalances,
        deposits,
        withdrawals,
        cancelledOrRejectedDeposits: cancelledDeposits,
        yieldByEpoch: yieldRecords,
        fixedTermDeposits: ftdRecords,
    };

    // Write output
    const outputDir = path.join(__dirname, 'output');
    const outputFile = path.join(outputDir, `tax-invoice-${fileSlug}.json`);
    fs.writeFileSync(outputFile, JSON.stringify(invoice, null, 2));

    console.log(`  ===== SUMMARY =====`);
    console.log(`  Depositor:         ${depositorAddress}`);
    console.log(`  Period:            ${periodLabel}`);
    console.log(`  Opening Balance:   $${openingBalance.toFixed(2)}`);
    console.log(`  Total Deposited:   $${totalDeposited.toFixed(2)}`);
    console.log(`  Total Withdrawn:   $${totalWithdrawn.toFixed(2)}`);
    console.log(`  Total Yield:       $${(totalYield + totalFtdInterest).toFixed(2)}`);
    console.log(`  Closing Balance:   $${closingBalance.toFixed(2)}`);
    console.log(`  Balance check:     $${(openingBalance + totalDeposited - totalWithdrawn + totalYield + totalFtdInterest).toFixed(2)} (should match closing)`);
    if (reportMode === 'monthly-summary') {
        console.log();
        console.log(`  Monthly Breakdown:`);
        for (const m of monthlyBreakdown) {
            console.log(`    ${m.month.padEnd(18)} Deposits: $${m.deposits.padStart(12)}  Yield: $${m.yieldEarned.padStart(10)}`);
        }
    }
    console.log();
    console.log(`  Output: ${outputFile}`);
    console.log();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
