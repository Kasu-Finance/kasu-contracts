import {
    createLendingPool,
    getDefaultLendingPoolConfig,
} from '../_modules/createLendingPool';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../../typechain-types/src/core/lendingPool/LendingPool';
import { getAccounts } from '../_modules/getAccounts';
import * as hre from 'hardhat';

async function main() {
    // signers
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];
    const adminAccountAddress = await adminAccount.getAddress();

    // LP1
    const createTranchesConfig_1: CreateTrancheConfigStruct[] = [
        {
            ratio: 15_00, // 15%
            interestRate: 5_040_862_203_635_605, // 30% APY
            minDepositAmount: 5_000_000, // 5 USDC
            maxDepositAmount: 300_000_000_000, // 300K USDC
        },
        {
            ratio: 85_00, // 85%
            interestRate: 2_174_299_640_020_476, // 12% APY
            minDepositAmount: 5_000_000, // 5 USDC
            maxDepositAmount: 1_700_000_000_000, // 1700K USDC
        },
    ];

    const createPoolConfig_1: CreatePoolConfigStruct = {
        poolName: 'Invoice Financing - Accounting Firms',
        poolSymbol: 'APXPFF',
        targetExcessLiquidityPercentage: 0,
        minExcessLiquidityPercentage: 0,
        tranches: createTranchesConfig_1,
        poolAdmin: adminAccountAddress, // ROLE_POOL_ADMIN
        drawRecipient: adminAccountAddress,
        desiredDrawAmount: BigInt(0),
    };

    await createLendingPool(createPoolConfig_1);

    // LP2
    const createTranchesConfig_2: CreateTrancheConfigStruct[] = [
        {
            ratio: 30_00,
            interestRate: 5_040_862_203_635_605, // 30% APY
            minDepositAmount: 5_000_000,
            maxDepositAmount: 600_000_000_000,
        },
        {
            ratio: 70_00,
            interestRate: 2_682_121_951_395_655, // 15% APY
            minDepositAmount: 5_000_000,
            maxDepositAmount: 1_400_000_000_000,
        },
    ];

    const createPoolConfig_2: CreatePoolConfigStruct = {
        poolName: 'Taxation Funding',
        poolSymbol: 'APXTXP',
        targetExcessLiquidityPercentage: 0,
        minExcessLiquidityPercentage: 0,
        tranches: createTranchesConfig_2,
        poolAdmin: adminAccountAddress, // ROLE_POOL_ADMIN
        drawRecipient: adminAccountAddress,
        desiredDrawAmount: BigInt(0),
    };

    await createLendingPool(createPoolConfig_2);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
