import fs from 'fs';
import path from 'path';
import puppeteer from 'puppeteer';

// ─── Types (mirror from generateTaxInvoice.ts) ──────────────────────────────

interface TaxInvoice {
    reportMode?: 'annual' | 'monthly-summary';
    depositor: string;
    chain: string;
    chainId: number;
    taxYear: number | null;
    startDate?: string;
    endDate?: string;
    periodLabel?: string;
    generatedAt: string;
    currency: string;
    blockRange: { startBlock: number; endBlock: number };
    summary: {
        totalDeposited: string;
        totalWithdrawn: string;
        totalYieldEarned: string;
        openingBalance: string;
        closingBalance: string;
    };
    monthlyBreakdown?: { month: string; monthKey: string; deposits: string; withdrawals: string; yieldEarned: string }[];
    openingBalances: { pool: string; strategy: string; tranche: string; trancheName: string; shares: string; usdcValue: string }[];
    closingBalances: { pool: string; strategy: string; tranche: string; trancheName: string; shares: string; usdcValue: string }[];
    deposits: { date: string; block: number; txHash: string; pool: string; strategy: string; tranche: string; trancheName: string; usdcAmount: string; sharesReceived: string }[];
    withdrawals: { date: string; block: number; txHash: string; pool: string; strategy: string; tranche: string; trancheName: string; usdcAmount: string; sharesBurned: string }[];
    cancelledOrRejectedDeposits: any[];
    yieldByEpoch: { epoch: number; epochStartDate: string; pool: string; strategy: string; tranche: string; trancheName: string; yieldUsdc: string; userShares: string; totalSupply: string }[];
    fixedTermDeposits: any[];
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function fmtUsd(value: string | number): string {
    const num = typeof value === 'string' ? parseFloat(value) : value;
    return num.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function shortAddr(addr: string): string {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

function aggregateYield(data: TaxInvoice) {
    const byStrategy: Record<string, { strategy: string; tranches: Record<string, number>; total: number }> = {};

    for (const y of data.yieldByEpoch) {
        if (!byStrategy[y.strategy]) {
            byStrategy[y.strategy] = { strategy: y.strategy, tranches: {}, total: 0 };
        }
        const amt = parseFloat(y.yieldUsdc);
        byStrategy[y.strategy].tranches[y.trancheName] = (byStrategy[y.strategy].tranches[y.trancheName] || 0) + amt;
        byStrategy[y.strategy].total += amt;
    }

    return byStrategy;
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function getPeriodLabel(data: TaxInvoice): string {
    return data.periodLabel || `Financial Year ${data.taxYear}`;
}

function getReportingPeriodDisplay(data: TaxInvoice): string {
    if (data.startDate && data.endDate) {
        const fmt = (iso: string) => {
            const [y, m, d] = iso.split('-');
            return `${d}.${m}.${y}`;
        };
        return `${fmt(data.startDate)} &ndash; ${fmt(data.endDate)}`;
    }
    return `01.01.${data.taxYear} &ndash; 31.12.${data.taxYear}`;
}

// ─── Monthly Summary HTML Template ──────────────────────────────────────────

function generateMonthlySummaryHtml(data: TaxInvoice): string {
    const generatedDate = new Date(data.generatedAt);
    const formattedGenDate = `${generatedDate.getUTCDate().toString().padStart(2, '0')}.${(generatedDate.getUTCMonth() + 1).toString().padStart(2, '0')}.${generatedDate.getUTCFullYear()}`;
    const monthly = data.monthlyBreakdown || [];

    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
    @page {
        size: A4;
        margin: 30mm 20mm 25mm 20mm;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
        font-size: 10px;
        color: #1a1a2e;
        line-height: 1.5;
        background: #fff;
    }

    .page { padding: 0 10px; }

    .header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        padding-bottom: 20px;
        border-bottom: 3px solid #1a1a2e;
        margin-bottom: 25px;
    }
    .logo-area h1 {
        font-size: 28px;
        font-weight: 700;
        letter-spacing: -0.5px;
        color: #1a1a2e;
    }
    .logo-area .subtitle {
        font-size: 11px;
        color: #666;
        margin-top: 2px;
    }
    .report-meta {
        text-align: right;
        font-size: 10px;
        color: #444;
    }
    .report-meta .report-title {
        font-size: 16px;
        font-weight: 600;
        color: #1a1a2e;
        margin-bottom: 4px;
    }

    .section-title {
        font-size: 13px;
        font-weight: 700;
        color: #1a1a2e;
        padding: 8px 0 6px 0;
        border-bottom: 1.5px solid #e0e0e0;
        margin: 20px 0 12px 0;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    .info-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px 40px;
        margin-bottom: 15px;
    }
    .info-row {
        display: flex;
        justify-content: space-between;
        padding: 3px 0;
    }
    .info-label { color: #666; font-size: 9.5px; text-transform: uppercase; letter-spacing: 0.3px; }
    .info-value { font-weight: 600; font-size: 10px; }

    .summary-cards {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 12px;
        margin: 15px 0;
    }
    .summary-card {
        background: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 6px;
        padding: 12px 14px;
    }
    .summary-card .card-label {
        font-size: 8.5px;
        text-transform: uppercase;
        letter-spacing: 0.4px;
        color: #666;
        margin-bottom: 4px;
    }
    .summary-card .card-value {
        font-size: 16px;
        font-weight: 700;
        color: #1a1a2e;
    }
    .summary-card.highlight {
        background: #1a1a2e;
        border-color: #1a1a2e;
    }
    .summary-card.highlight .card-label { color: #aaa; }
    .summary-card.highlight .card-value { color: #fff; }

    table {
        width: 100%;
        border-collapse: collapse;
        margin: 8px 0 15px 0;
        font-size: 9.5px;
    }
    th {
        text-align: left;
        font-size: 8.5px;
        text-transform: uppercase;
        letter-spacing: 0.3px;
        color: #666;
        padding: 6px 8px;
        border-bottom: 1.5px solid #ddd;
        font-weight: 600;
    }
    th.right, td.right { text-align: right; }
    td {
        padding: 6px 8px;
        border-bottom: 1px solid #f0f0f0;
        vertical-align: top;
    }
    tr.grand-total td {
        border-top: 2px solid #1a1a2e;
        font-weight: 700;
        font-size: 10.5px;
        padding-top: 10px;
        color: #1a1a2e;
    }

    .footer {
        margin-top: 15px;
        padding-top: 10px;
        border-top: 1px solid #e0e0e0;
        font-size: 8px;
        color: #999;
        line-height: 1.5;
    }
    .footer p { margin-bottom: 2px; }
</style>
</head>
<body>
<div class="page">

    <!-- Header -->
    <div class="header">
        <div class="logo-area">
            <h1>KASU</h1>
            <div class="subtitle">Private Credit Lending Platform</div>
        </div>
        <div class="report-meta">
            <div class="report-title">Monthly Lender Report</div>
            <div>${getPeriodLabel(data)}</div>
            <div>Generated: ${formattedGenDate}</div>
        </div>
    </div>

    <!-- Lender Info -->
    <div class="section-title">Lender Details</div>
    <div class="info-grid">
        <div>
            <div class="info-row">
                <span class="info-label">Wallet Address</span>
                <span class="info-value" style="font-family: monospace; font-size: 9px;">${data.depositor}</span>
            </div>
        </div>
        <div>
            <div class="info-row">
                <span class="info-label">Network</span>
                <span class="info-value">${data.chain}</span>
            </div>
            <div class="info-row">
                <span class="info-label">Reporting Period</span>
                <span class="info-value">${getReportingPeriodDisplay(data)}</span>
            </div>
        </div>
    </div>

    <!-- Summary -->
    <div class="section-title">Financial Summary</div>
    <div class="summary-cards">
        <div class="summary-card">
            <div class="card-label">Total Deposited</div>
            <div class="card-value">$${fmtUsd(data.summary.totalDeposited)}</div>
        </div>
        <div class="summary-card">
            <div class="card-label">Total Withdrawn</div>
            <div class="card-value">$${fmtUsd(data.summary.totalWithdrawn)}</div>
        </div>
        <div class="summary-card highlight">
            <div class="card-label">Interest Earned</div>
            <div class="card-value">$${fmtUsd(data.summary.totalYieldEarned)}</div>
        </div>
        <div class="summary-card">
            <div class="card-label">Closing Balance</div>
            <div class="card-value">$${fmtUsd(data.summary.closingBalance)}</div>
        </div>
    </div>

    <!-- Monthly Breakdown -->
    <div class="section-title">Monthly Breakdown</div>
    <table>
        <thead>
            <tr>
                <th>Month</th>
                <th class="right">Deposits (USDC)</th>
                <th class="right">Withdrawals (USDC)</th>
                <th class="right">Interest Earned (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${monthly.map((m) =>
                `<tr>
                    <td>${m.month}</td>
                    <td class="right">${parseFloat(m.deposits) > 0 ? '$' + fmtUsd(m.deposits) : '&mdash;'}</td>
                    <td class="right">${parseFloat(m.withdrawals) > 0 ? '$' + fmtUsd(m.withdrawals) : '&mdash;'}</td>
                    <td class="right">${parseFloat(m.yieldEarned) > 0 ? '$' + fmtUsd(m.yieldEarned) : '&mdash;'}</td>
                </tr>`
            ).join('\n')}
            <tr class="grand-total">
                <td>Total</td>
                <td class="right">$${fmtUsd(data.summary.totalDeposited)}</td>
                <td class="right">$${fmtUsd(data.summary.totalWithdrawn)}</td>
                <td class="right">$${fmtUsd(data.summary.totalYieldEarned)}</td>
            </tr>
        </tbody>
    </table>

    ${data.closingBalances.length > 0 ? `
    <!-- Closing Balances -->
    <div class="section-title">Current Position</div>
    <table>
        <thead>
            <tr>
                <th>Strategy</th>
                <th>Tranche</th>
                <th class="right">Value (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${data.closingBalances.map((b) =>
                `<tr>
                    <td>${b.strategy}</td>
                    <td>${b.trancheName}</td>
                    <td class="right">$${fmtUsd(b.usdcValue)}</td>
                </tr>`
            ).join('\n')}
            <tr class="grand-total">
                <td colspan="2">Total</td>
                <td class="right">$${fmtUsd(data.summary.closingBalance)}</td>
            </tr>
        </tbody>
    </table>
    ` : ''}

    <!-- Footer -->
    <div class="footer">
        <p>This report has been generated from on-chain data on ${data.chain} (Chain ID: ${data.chainId}), block range ${data.blockRange.startBlock.toLocaleString()} &ndash; ${data.blockRange.endBlock.toLocaleString()}.</p>
        <p>All amounts are denominated in USDC. Interest is calculated epoch-by-epoch based on proportional share ownership at the time of each clearing event. This report is provided for informational purposes only and does not constitute tax advice.</p>
        <p style="margin-top: 8px; color: #bbb;">Kasu Protocol &mdash; kasu.finance</p>
    </div>

</div>
</body>
</html>`;
}

// ─── Annual HTML Template ───────────────────────────────────────────────────

function generateHtml(data: TaxInvoice): string {
    const yieldByStrategy = aggregateYield(data);
    const generatedDate = new Date(data.generatedAt);
    const formattedGenDate = `${generatedDate.getUTCDate().toString().padStart(2, '0')}.${(generatedDate.getUTCMonth() + 1).toString().padStart(2, '0')}.${generatedDate.getUTCFullYear()}`;

    // Group deposits by date
    const depositsByDate: Record<string, typeof data.deposits> = {};
    for (const d of data.deposits) {
        if (!depositsByDate[d.date]) depositsByDate[d.date] = [];
        depositsByDate[d.date].push(d);
    }

    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
    @page {
        size: A4;
        margin: 30mm 20mm 25mm 20mm;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
        font-size: 10px;
        color: #1a1a2e;
        line-height: 1.5;
        background: #fff;
    }

    .page { padding: 0 10px; }

    /* Header */
    .header {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        padding-bottom: 20px;
        border-bottom: 3px solid #1a1a2e;
        margin-bottom: 25px;
    }
    .logo-area h1 {
        font-size: 28px;
        font-weight: 700;
        letter-spacing: -0.5px;
        color: #1a1a2e;
    }
    .logo-area .subtitle {
        font-size: 11px;
        color: #666;
        margin-top: 2px;
    }
    .report-meta {
        text-align: right;
        font-size: 10px;
        color: #444;
    }
    .report-meta .report-title {
        font-size: 16px;
        font-weight: 600;
        color: #1a1a2e;
        margin-bottom: 4px;
    }

    /* Section titles */
    .section-title {
        font-size: 13px;
        font-weight: 700;
        color: #1a1a2e;
        padding: 8px 0 6px 0;
        border-bottom: 1.5px solid #e0e0e0;
        margin: 20px 0 12px 0;
        text-transform: uppercase;
        letter-spacing: 0.5px;
    }

    /* Info block */
    .info-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px 40px;
        margin-bottom: 15px;
    }
    .info-row {
        display: flex;
        justify-content: space-between;
        padding: 3px 0;
    }
    .info-label { color: #666; font-size: 9.5px; text-transform: uppercase; letter-spacing: 0.3px; }
    .info-value { font-weight: 600; font-size: 10px; }

    /* Summary cards */
    .summary-cards {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 12px;
        margin: 15px 0;
    }
    .summary-card {
        background: #f8f9fa;
        border: 1px solid #e9ecef;
        border-radius: 6px;
        padding: 12px 14px;
    }
    .summary-card .card-label {
        font-size: 8.5px;
        text-transform: uppercase;
        letter-spacing: 0.4px;
        color: #666;
        margin-bottom: 4px;
    }
    .summary-card .card-value {
        font-size: 16px;
        font-weight: 700;
        color: #1a1a2e;
    }
    .summary-card.highlight {
        background: #1a1a2e;
        border-color: #1a1a2e;
    }
    .summary-card.highlight .card-label { color: #aaa; }
    .summary-card.highlight .card-value { color: #fff; }

    /* Tables */
    table {
        width: 100%;
        border-collapse: collapse;
        margin: 8px 0 15px 0;
        font-size: 9.5px;
    }
    th {
        text-align: left;
        font-size: 8.5px;
        text-transform: uppercase;
        letter-spacing: 0.3px;
        color: #666;
        padding: 6px 8px;
        border-bottom: 1.5px solid #ddd;
        font-weight: 600;
    }
    th.right, td.right { text-align: right; }
    td {
        padding: 6px 8px;
        border-bottom: 1px solid #f0f0f0;
        vertical-align: top;
    }
    tr.subtotal td {
        border-top: 1px solid #ccc;
        font-weight: 700;
        padding-top: 8px;
    }
    tr.grand-total td {
        border-top: 2px solid #1a1a2e;
        font-weight: 700;
        font-size: 10.5px;
        padding-top: 10px;
        color: #1a1a2e;
    }
    tr.strategy-header td {
        font-weight: 700;
        padding-top: 10px;
        color: #1a1a2e;
        border-bottom: none;
        font-size: 10px;
    }

    /* Closing balance table */
    .balance-table td:first-child { padding-left: 16px; }

    /* Footer */
    .footer {
        margin-top: 30px;
        padding-top: 15px;
        border-top: 1px solid #e0e0e0;
        font-size: 8.5px;
        color: #999;
        line-height: 1.6;
    }
    .footer p { margin-bottom: 4px; }

    /* Deposit table strategy grouping */
    .deposit-date-row td {
        font-weight: 600;
        color: #1a1a2e;
        background: #f8f9fa;
        border-bottom: 1px solid #e0e0e0;
    }
</style>
</head>
<body>
<div class="page">

    <!-- Header -->
    <div class="header">
        <div class="logo-area">
            <h1>KASU</h1>
            <div class="subtitle">Private Credit Lending Platform</div>
        </div>
        <div class="report-meta">
            <div class="report-title">Lender Tax Report</div>
            <div>${getPeriodLabel(data)}</div>
            <div>Generated: ${formattedGenDate}</div>
        </div>
    </div>

    <!-- Lender Info -->
    <div class="section-title">Lender Details</div>
    <div class="info-grid">
        <div>
            <div class="info-row">
                <span class="info-label">Wallet Address</span>
                <span class="info-value" style="font-family: monospace; font-size: 9px;">${data.depositor}</span>
            </div>
        </div>
        <div>
            <div class="info-row">
                <span class="info-label">Network</span>
                <span class="info-value">${data.chain}</span>
            </div>
            <div class="info-row">
                <span class="info-label">Reporting Period</span>
                <span class="info-value">${getReportingPeriodDisplay(data)}</span>
            </div>
        </div>
    </div>

    <!-- Summary -->
    <div class="section-title">Financial Summary</div>
    <div class="summary-cards">
        <div class="summary-card">
            <div class="card-label">Total Deposited</div>
            <div class="card-value">$${fmtUsd(data.summary.totalDeposited)}</div>
        </div>
        <div class="summary-card">
            <div class="card-label">Total Withdrawn</div>
            <div class="card-value">$${fmtUsd(data.summary.totalWithdrawn)}</div>
        </div>
        <div class="summary-card highlight">
            <div class="card-label">Yield Earned</div>
            <div class="card-value">$${fmtUsd(data.summary.totalYieldEarned)}</div>
        </div>
        <div class="summary-card">
            <div class="card-label">Closing Balance</div>
            <div class="card-value">$${fmtUsd(data.summary.closingBalance)}</div>
        </div>
    </div>

    <!-- Yield Breakdown -->
    <div class="section-title">Yield Breakdown by Strategy</div>
    <table>
        <thead>
            <tr>
                <th>Strategy</th>
                <th>Tranche</th>
                <th class="right">Yield Earned (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${Object.values(yieldByStrategy).map((s) => {
                const trancheRows = Object.entries(s.tranches)
                    .sort(([a], [b]) => {
                        const order: Record<string, number> = { Senior: 0, Mezzanine: 1, Junior: 2 };
                        return (order[a] ?? 3) - (order[b] ?? 3);
                    })
                    .map(([tranche, amount]) =>
                        `<tr><td></td><td>${tranche}</td><td class="right">$${fmtUsd(amount)}</td></tr>`
                    ).join('\n');
                return `
                    <tr class="strategy-header"><td colspan="2">${s.strategy}</td><td></td></tr>
                    ${trancheRows}
                    <tr class="subtotal"><td></td><td>Subtotal</td><td class="right">$${fmtUsd(s.total)}</td></tr>
                `;
            }).join('\n')}
            <tr class="grand-total">
                <td colspan="2">Total Yield Earned</td>
                <td class="right">$${fmtUsd(data.summary.totalYieldEarned)}</td>
            </tr>
        </tbody>
    </table>

    <!-- Deposit Activity -->
    <div class="section-title">Deposit Activity</div>
    <table>
        <thead>
            <tr>
                <th>Date</th>
                <th>Strategy</th>
                <th>Tranche</th>
                <th class="right">Amount (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${data.deposits.map((d) =>
                `<tr>
                    <td>${d.date}</td>
                    <td>${d.strategy}</td>
                    <td>${d.trancheName}</td>
                    <td class="right">$${fmtUsd(d.usdcAmount)}</td>
                </tr>`
            ).join('\n')}
            <tr class="grand-total">
                <td colspan="3">Total Deposited</td>
                <td class="right">$${fmtUsd(data.summary.totalDeposited)}</td>
            </tr>
        </tbody>
    </table>

    ${data.withdrawals.length > 0 ? `
    <!-- Withdrawal Activity -->
    <div class="section-title">Withdrawal Activity</div>
    <table>
        <thead>
            <tr>
                <th>Date</th>
                <th>Strategy</th>
                <th>Tranche</th>
                <th class="right">Amount (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${data.withdrawals.map((w) =>
                `<tr>
                    <td>${w.date}</td>
                    <td>${w.strategy}</td>
                    <td>${w.trancheName}</td>
                    <td class="right">$${fmtUsd(w.usdcAmount)}</td>
                </tr>`
            ).join('\n')}
            <tr class="grand-total">
                <td colspan="3">Total Withdrawn</td>
                <td class="right">$${fmtUsd(data.summary.totalWithdrawn)}</td>
            </tr>
        </tbody>
    </table>
    ` : ''}

    <!-- Closing Balances -->
    <div class="section-title">Closing Position</div>
    <table class="balance-table">
        <thead>
            <tr>
                <th>Strategy</th>
                <th>Tranche</th>
                <th class="right">Value (USDC)</th>
            </tr>
        </thead>
        <tbody>
            ${data.closingBalances.map((b) =>
                `<tr>
                    <td>${b.strategy}</td>
                    <td>${b.trancheName}</td>
                    <td class="right">$${fmtUsd(b.usdcValue)}</td>
                </tr>`
            ).join('\n')}
            <tr class="grand-total">
                <td colspan="2">Total Closing Balance</td>
                <td class="right">$${fmtUsd(data.summary.closingBalance)}</td>
            </tr>
        </tbody>
    </table>

    <!-- Footer -->
    <div class="footer">
        <p>This report has been generated from on-chain data on ${data.chain} (Chain ID: ${data.chainId}), block range ${data.blockRange.startBlock.toLocaleString()} &ndash; ${data.blockRange.endBlock.toLocaleString()}.</p>
        <p>All amounts are denominated in USDC. Yield is calculated epoch-by-epoch based on proportional share ownership at the time of each clearing event. This report is provided for informational purposes only and does not constitute tax advice. Please consult a qualified tax professional for guidance specific to your jurisdiction.</p>
        <p style="margin-top: 8px; color: #bbb;">Kasu Protocol &mdash; kasu.finance</p>
    </div>

</div>
</body>
</html>`;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
    const inputFile = process.argv[2];
    if (!inputFile) {
        // Default: find the most recent invoice
        const outputDir = path.join(__dirname, 'output');
        const files = fs.readdirSync(outputDir).filter((f) => f.endsWith('.json'));
        if (files.length === 0) {
            console.error('No invoice JSON files found. Run generateTaxInvoice.ts first.');
            process.exit(1);
        }
        const latestFile = files.sort().pop()!;
        console.log(`  Using: ${latestFile}`);
        return generatePdf(path.join(outputDir, latestFile));
    }
    return generatePdf(inputFile);
}

async function generatePdf(jsonPath: string) {
    console.log(`\n  PDF Tax Report Generator`);
    console.log(`  ========================`);

    const data: TaxInvoice = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
    const mode = data.reportMode || 'annual';
    console.log(`  Depositor: ${data.depositor}`);
    console.log(`  Period:    ${data.periodLabel || `FY ${data.taxYear}`}`);
    console.log(`  Mode:      ${mode}`);

    const html = mode === 'monthly-summary' ? generateMonthlySummaryHtml(data) : generateHtml(data);

    // Write HTML for debugging
    const htmlPath = jsonPath.replace('.json', '.html');
    fs.writeFileSync(htmlPath, html);
    console.log(`  HTML:      ${htmlPath}`);

    // Generate PDF
    const browser = await puppeteer.launch({ headless: true });
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'networkidle0' });

    const pdfPath = jsonPath.replace('.json', '.pdf');
    await page.pdf({
        path: pdfPath,
        format: 'A4',
        printBackground: true,
        margin: { top: '20mm', bottom: '20mm', left: '15mm', right: '15mm' },
    });

    await browser.close();

    console.log(`  PDF:       ${pdfPath}`);
    console.log();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
