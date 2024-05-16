import path from 'path';
import fs from 'fs';
import {
    KasuController__factory,
    LendingPoolFactory__factory,
    LendingPoolManager__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../../typechain-types/src/core/lendingPool/LendingPool';
import { ContractTransactionResponse } from 'ethers';
import { getLogFilePath } from './_logs';

export async function createLendingPool(
    poolName: string,
    poolSymbol: string,
    numberOfTranches: number,
) {
    let tx: ContractTransactionResponse;

    const { filePath } = getLogFilePath(hre.network.name);
    const deploymentAddresses = JSON.parse(
        fs.readFileSync(filePath).toString(),
    );

    // signers
    const signers = await hre.ethers.getSigners();

    const deployerAccount = signers[0];
    const adminAccount = signers[0];

    const clearingManagerAccount = signers[0];
    const poolCreatorAccount = signers[0];
    const poolAdminAccount = signers[0];
    const drawRecipientAccount = signers[0];

    console.info('adminAccount', adminAccount.address);
    console.info('clearingManagerAccount', clearingManagerAccount.address);
    console.info('poolCreatorAccount', poolCreatorAccount.address);
    console.info('poolAdminAccount', poolAdminAccount.address);
    console.info('drawRecipientAccount', poolAdminAccount.address);

    // access control
    console.info(
        `Granting ROLE_LENDING_POOL_CREATOR role to ${adminAccount.address}`,
    );
    const kasuControllerAdmin = KasuController__factory.connect(
        deploymentAddresses['KasuController'].address,
        adminAccount,
    );

    const ROLE_LENDING_POOL_CREATOR = hre.ethers.id(
        'ROLE_LENDING_POOL_CREATOR',
    );
    tx = await kasuControllerAdmin.grantRole(
        ROLE_LENDING_POOL_CREATOR,
        poolCreatorAccount,
    );
    await tx.wait(1);

    // create lending pool
    console.info(`Creating Lending Pool`);
    console.info(`lending pool name: ${poolName}`);
    console.info(`lending pool symbol: ${poolSymbol}`);
    console.info(`number of tranches: ${numberOfTranches}`);

    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses['LendingPoolManager'].address,
        poolCreatorAccount,
    );

    const createTranchesConfig: CreateTrancheConfigStruct[] = [];

    const ratios = [[100_00], [30_00, 70_00], [15_00, 35_00, 50_00]];

    if (numberOfTranches >= 1) {
        const juniorTrancheConfig: CreateTrancheConfigStruct = {
            ratio: ratios[numberOfTranches - 1][0],
            interestRate: 2500000000000000, //
            minDepositAmount: 50_000_000, // 50 USDC
            maxDepositAmount: 10_000_000_000, // 100K USDC
        };
        createTranchesConfig.push(juniorTrancheConfig);
    }

    if (numberOfTranches >= 2) {
        const mezzoTrancheConfig: CreateTrancheConfigStruct = {
            ratio: ratios[numberOfTranches - 1][1],
            interestRate: 2000000000000000,
            minDepositAmount: 50_000_000,
            maxDepositAmount: 10_000_000_000,
        };
        createTranchesConfig.push(mezzoTrancheConfig);
    }

    if (numberOfTranches >= 3) {
        const seniorTrancheConfig: CreateTrancheConfigStruct = {
            ratio: ratios[numberOfTranches - 1][2],
            interestRate: 1500000000000000,
            minDepositAmount: 50_000_000,
            maxDepositAmount: 100_000_000_000,
        };
        createTranchesConfig.push(seniorTrancheConfig);
    }

    const createPoolConfig: CreatePoolConfigStruct = {
        poolName: poolName,
        poolSymbol: poolSymbol,
        targetExcessLiquidityPercentage: BigInt(10_000),
        minExcessLiquidityPercentage: 0,
        tranches: createTranchesConfig,
        poolAdmin: poolAdminAccount.address,
        drawRecipient: drawRecipientAccount.address,
        desiredDrawAmount: BigInt(0),
    };

    tx = await lendingPoolManagerAdmin.createPool(createPoolConfig);
    const txReceipt = await tx.wait(1);

    // get new lending pool address
    const lendingPoolFactory = LendingPoolFactory__factory.connect(
        deploymentAddresses['LendingPoolFactory'].address,
        adminAccount,
    );

    const allPoolCreatedFilter = lendingPoolFactory.filters.PoolCreated();
    const allPoolCreatedEvents = await lendingPoolFactory.queryFilter(
        allPoolCreatedFilter,
        txReceipt ? txReceipt.blockNumber : undefined,
    );

    const lastEvent = allPoolCreatedEvents[allPoolCreatedEvents.length - 1];
    const createdLendingPoolAddress = lastEvent.args[1].lendingPool;
    const createdPendingPoolAddress = lastEvent.args[1].pendingPool;
    const createdTrancheAddresses = lastEvent.args[1].tranches;

    console.info('LendingPool Address:', createdLendingPoolAddress);
    console.info('PendingPool Address:', createdPendingPoolAddress);
    console.info('Tranche Addresses"', createdTrancheAddresses);

    const ROLE_POOL_CLEARING_MANAGER = hre.ethers.id(
        'ROLE_POOL_CLEARING_MANAGER',
    );
    tx = await kasuControllerAdmin
        .connect(poolAdminAccount)
        .grantLendingPoolRole(
            createdLendingPoolAddress,
            ROLE_POOL_CLEARING_MANAGER,
            clearingManagerAccount.address,
        );
    await tx.wait(1);

    return {
        createdLendingPoolAddress,
        createdPendingPoolAddress,
        createdTrancheAddresses,
    };
}
