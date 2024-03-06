import * as addresses from '../deployments/localhost/addresses-localhost.json';
import {
    KasuController__factory,
    LendingPoolManager__factory,
    SystemVariables__factory,
} from '../typechain-types';
import * as hre from 'hardhat';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../typechain-types/src/core/lendingPool/LendingPool';
import { ContractTransactionResponse } from 'ethers';
import { SystemVariablesSetupStruct } from '../typechain-types/src/core/SystemVariables';

async function main() {
    let tx: ContractTransactionResponse;

    // signers
    const namedSigners = await hre.ethers.getNamedSigners();
    const admin = namedSigners['admin'];

    const unNamedSigners = await hre.ethers.getUnnamedSigners();
    const poolCreatorAccount = unNamedSigners[0];
    const poolAdminAccount = unNamedSigners[1];
    const borrowRecipientAccount = unNamedSigners[2];

    // contracts connect
    const lendingPoolManager = LendingPoolManager__factory.connect(
        addresses['LendingPoolManager'].address,
        poolCreatorAccount,
    );
    const kasuController = KasuController__factory.connect(
        addresses['KasuController'].address,
        admin,
    );
    const systemVariables = SystemVariables__factory.connect(
        addresses['SystemVariables'].address,
        admin,
    );

    // system variables
    if (shouldInitialiseSystemVariables()) {
        const systemVariablesSetup: SystemVariablesSetupStruct = {
            firstEpochStartTimestamp:
                Math.round(Date.now() / 1000) + 3600 * 24 * 3,
            clearingPeriodLength: 1,
            protocolFee: 10_00,
            loyaltyThresholds: [10_00, 20_00, 30_00],
            defaultTrancheInterestChangeEpochDelay: 1,
        };
        console.info('Initializing System Variables');
        tx = await systemVariables.initialize(systemVariablesSetup);
        await tx.wait(1);
    }

    // access control
    const ROLE_LENDING_POOL_CREATOR = hre.ethers.id(
        'ROLE_LENDING_POOL_CREATOR',
    );
    console.info('Granting ROLE_LENDING_POOL_CREATOR role');
    tx = await kasuController.grantRole(
        ROLE_LENDING_POOL_CREATOR,
        poolCreatorAccount,
    );
    await tx.wait(1);

    // create lending pool
    const juniorTrancheConfig: CreateTrancheConfigStruct = {
        trancheName: 'test junior tranche',
        trancheSymbol: 'JT',
        ratio: 20_00, // 20%
        interestRate: 3_00, // 10%
        minDepositAmount: 500_000_000, // 500 USDC
        maxDepositAmount: 3000_000_000, // 3000 USDC
    };
    const mezzoTrancheConfig: CreateTrancheConfigStruct = {
        trancheName: 'test mezzo tranche',
        trancheSymbol: 'MT',
        ratio: 30_00,
        interestRate: 2_00,
        minDepositAmount: 100_000_000,
        maxDepositAmount: 10_000_000_000,
    };
    const seniorTrancheConfig: CreateTrancheConfigStruct = {
        trancheName: 'test senior tranche',
        trancheSymbol: 'ST',
        ratio: 50_00,
        interestRate: 1_00,
        minDepositAmount: 10_000_000,
        maxDepositAmount: 100_000_000_000,
    };
    const createPoolConfig: CreatePoolConfigStruct = {
        poolName: 'test lending pool',
        poolSymbol: 'LP',
        targetExcessLiquidityPercentage: BigInt(10_000),
        tranches: [
            juniorTrancheConfig,
            mezzoTrancheConfig,
            seniorTrancheConfig,
        ],
        poolAdmin: poolAdminAccount.address,
        borrowRecipient: borrowRecipientAccount.address,
        totalDesiredLoanAmount: BigInt(100_000_000_000),
    };
    console.info('Creating Lending Pool');
    tx = await lendingPoolManager.createPool(createPoolConfig);
    await tx.wait(1);
}

function shouldInitialiseSystemVariables() {
    return process.env['INIT_SYSTEM_VARS'] === '1';
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
