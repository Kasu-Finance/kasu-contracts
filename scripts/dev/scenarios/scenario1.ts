import { parseKasuError } from '../../_utils/parseErrors';
import { getAccounts } from '../../_modules/getAccounts';
import * as hre from 'hardhat';
import { deploymentFileFactory } from '../../_utils/deploymentFileFactory';
import {
    createLendingPool,
    getDefaultLendingPoolConfig,
} from '../../_modules/createLendingPool';
import { ClearingConfigurationStruct } from '../../../typechain-types/src/core/clearing/ClearingSteps';
import {
    RequestDepositInput,
    requestDeposits,
} from '../../_modules/requestDeposit';
import { ethers } from 'hardhat';
import {
    ClearingCoordinator__factory,
    LendingPoolManager__factory,
} from '../../../typechain-types';
import { ContractTransactionResponse } from 'ethers';
import { runClearing } from '../_modules/runClearing';
import { addFixedTermDeposit } from '../../_modules/addFixedTermDeposit';
import { addFixedTermDepositConfigAllowlist } from '../../_modules/addFixedTermDepositConfigAllowlist';

function toUSDC(usd: bigint): bigint {
    return ethers.parseUnits(usd.toString(), 6);
}

async function main() {
    // accounts
    const signers = await getAccounts(hre.network.name);
    const adminAccount = signers[1];
    const aliceAccount = signers[2];

    // get deployment addresses
    const deploymentFile = deploymentFileFactory(hre.network.name);
    const deploymentAddresses = deploymentFile.getContractAddresses();

    try {
        // create a lending pool (three tranches)
        const numberOfTranches = 3;
        const createdLendingPool = await createLendingPool(
            await getDefaultLendingPoolConfig(
                'S1 lending pool',
                'S1LP',
                numberOfTranches,
            ),
        );
        const lp = createdLendingPool.lendingPoolAddress;
        const lp_junior = createdLendingPool.trancheAddresses[0];
        const lp_mezzanine = createdLendingPool.trancheAddresses[1];
        const lp_senior = createdLendingPool.trancheAddresses[2];

        const clearingManagerAccount =
            createdLendingPool.roles.clearingManagerAccount;
        const poolManagerAccount = createdLendingPool.roles.poolManagerAccount;
        const poolAdminAccount = createdLendingPool.roles.poolAdminAccount;

        // configure system
        let tx: ContractTransactionResponse;
        const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
            deploymentAddresses.LendingPoolManager.address,
            poolManagerAccount,
        );

        tx = await lendingPoolManagerAdmin.updateMaximumDepositAmount(
            lp,
            lp_junior,
            toUSDC(3_000_000n),
        );
        await tx.wait(1);

        tx = await lendingPoolManagerAdmin.updateMaximumDepositAmount(
            lp,
            lp_mezzanine,
            toUSDC(3_000_000n),
        );
        await tx.wait(1);

        tx = await lendingPoolManagerAdmin.updateMaximumDepositAmount(
            lp,
            lp_senior,
            toUSDC(3_000_000n),
        );
        await tx.wait(1);

        const ftdConfigId1 = await addFixedTermDeposit(
            lp,
            {
                tranche: lp_senior,
                epochLockDuration: 2,  
                epochInterestRate: 1800000000000000,
                whitelistedOnly: false
            },
            adminAccount
        );

        const ftdConfigId2 = await addFixedTermDeposit(
            lp,
            {
                tranche: lp_senior,
                epochLockDuration: 2,  
                epochInterestRate: 1900000000000000,
                whitelistedOnly: true
            },
            adminAccount
        );

        await addFixedTermDepositConfigAllowlist(
            lp,
            ftdConfigId2,
            [(await aliceAccount.getAddress())],
            [true],
            adminAccount
        )

        // available funds
        const clearingCoordinator = ClearingCoordinator__factory.connect(
            deploymentAddresses.ClearingCoordinator.address,
            poolAdminAccount,
        );

        // ### epoch 1rst ###
        console.info('### Epoch 1rst ###');
        // deposit request (J 130K, M 16K, S 4K)
        const requestDepositsEpoch1: RequestDepositInput[] = [
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_junior,
                amount: toUSDC(130_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_mezzanine,
                amount: toUSDC(16_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_senior,
                amount: toUSDC(4_000n),
                ftdConfigId: ftdConfigId1,
            },
        ];
        await requestDeposits(requestDepositsEpoch1, true, true);
        // clearing (20%,10%,70%, total 100K, draw 100K, 10% max excess)
        let availableFunds = await clearingCoordinator.lendingPoolMaxDrawAmount(lp);
        const clearingConfigurationEpoch1: ClearingConfigurationStruct = {
            drawAmount: availableFunds,
            trancheDesiredRatios: [20_00, 10_00, 70_00],
            maxExcessPercentage: 10_00,
            minExcessPercentage: 0,
        };
        await runClearing(
            lp,
            clearingConfigurationEpoch1,
            clearingManagerAccount,
            adminAccount,
        );

        // ### epoch 2nd ###
        console.info('### Epoch 2nd ###');
        // deposit request (J 1000K, M 100K, S 36K)
        const requestDepositsEpoch2: RequestDepositInput[] = [
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_junior,
                amount: toUSDC(1_000_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_mezzanine,
                amount: toUSDC(100_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_senior,
                amount: toUSDC(36_000n),
                ftdConfigId: ftdConfigId2,
            },
        ];
        await requestDeposits(requestDepositsEpoch2, true, false);
        // clearing (20%,10%,70%, total 550K, draw 500K, 10% max excess)
        availableFunds = await clearingCoordinator.lendingPoolMaxDrawAmount(lp);
        const clearingConfigurationEpoch2: ClearingConfigurationStruct = {
            drawAmount: availableFunds,
            trancheDesiredRatios: [20_00, 10_00, 70_00],
            maxExcessPercentage: 10_00,
            minExcessPercentage: 0,
        };
        await runClearing(
            lp,
            clearingConfigurationEpoch2,
            clearingManagerAccount,
            adminAccount,
        );

        // ### epoch 3rd ###
        console.info('### Epoch 3rd ###');
        // deposit request (J 464K, M 27K, S 1K)
        const requestDepositsEpoch3: RequestDepositInput[] = [
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_junior,
                amount: toUSDC(464_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_mezzanine,
                amount: toUSDC(27_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_senior,
                amount: toUSDC(1_000n),
                ftdConfigId: 0n,
            },
        ];
        await requestDeposits(requestDepositsEpoch3, true, false);
        // clearing (20%,10%,70%, total 770K, draw 700K, 10% max excess)
        availableFunds = await clearingCoordinator.lendingPoolMaxDrawAmount(lp);
        const clearingConfigurationEpoch3: ClearingConfigurationStruct = {
            drawAmount: availableFunds,
            trancheDesiredRatios: [20_00, 10_00, 70_00],
            maxExcessPercentage: 10_00,
            minExcessPercentage: 0,
        };
        await runClearing(
            lp,
            clearingConfigurationEpoch3,
            clearingManagerAccount,
            adminAccount,
        );

        // ### epoch 4th ###
        console.info('### Epoch 4th ###');
        // deposit request (J 3000K, M 500K, S 200K)
        const requestDepositsEpoch4: RequestDepositInput[] = [
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_junior,
                amount: toUSDC(3_000_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_mezzanine,
                amount: toUSDC(500_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_senior,
                amount: toUSDC(200_000n),
                ftdConfigId: 0n,
            },
        ];
        await requestDeposits(requestDepositsEpoch4, true, false);
        // clearing (20%,10%,70%, total 1320K, draw 1200K, 10% max excess)
        availableFunds = await clearingCoordinator.lendingPoolMaxDrawAmount(lp);
        const clearingConfigurationEpoch4: ClearingConfigurationStruct = {
            drawAmount: availableFunds,
            trancheDesiredRatios: [20_00, 10_00, 70_00],
            maxExcessPercentage: 10_00,
            minExcessPercentage: 0,
        };
        await runClearing(
            lp,
            clearingConfigurationEpoch4,
            clearingManagerAccount,
            adminAccount,
        );

        // ### epoch 5th ###
        console.info('### Epoch 5th ###');
        // deposit request (J 2K, M 15K, S 2000K)
        const requestDepositsEpoch5: RequestDepositInput[] = [
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_junior,
                amount: toUSDC(2_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_mezzanine,
                amount: toUSDC(15_000n),
                ftdConfigId: 0n,
            },
            {
                user: aliceAccount,
                lendingPoolAddress: lp,
                trancheAddress: lp_senior,
                amount: toUSDC(2_000_000n),
                ftdConfigId: 0n,
            },
        ];
        await requestDeposits(requestDepositsEpoch5, true, false);
        // clearing (20%,10%,70%, total 1320K, draw 1200K, 10% max excess)
        availableFunds = await clearingCoordinator.lendingPoolMaxDrawAmount(lp);
        const clearingConfigurationEpoch5: ClearingConfigurationStruct = {
            drawAmount: availableFunds,
            trancheDesiredRatios: [20_00, 10_00, 70_00],
            maxExcessPercentage: 10_00,
            minExcessPercentage: 0,
        };
        await runClearing(
            lp,
            clearingConfigurationEpoch5,
            clearingManagerAccount,
            adminAccount,
        );
    } catch (error: any) {
        parseKasuError(error);
    }
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
