import {
    LendingPoolFactory__factory,
    LendingPoolManager__factory,
} from '../../typechain-types';
import * as hre from 'hardhat';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../../typechain-types/src/core/lendingPool/LendingPool';
import { ContractTransactionResponse } from 'ethers';
import { deploymentFileFactory } from '../_utils/deploymentFileFactory';
import {
    grantLendingPoolRole,
    ROLE_POOL_CLEARING_MANAGER,
    ROLE_POOL_FUNDS_MANAGER,
    ROLE_POOL_MANAGER,
    ROLE_PROTOCOL_FEE_CLAIMER,
} from './grantLendingPoolRole';
import { getAccounts } from './getAccounts';
import { grantRole, ROLE_LENDING_POOL_CREATOR } from './grantRole';

export async function createLendingPool(
    poolName: string,
    poolSymbol: string,
    numberOfTranches: number,
) {
    let tx: ContractTransactionResponse;

    const addressFile = deploymentFileFactory(hre.network.name, 0);
    const deploymentAddresses = addressFile.getContractAddresses();

    // signers
    const signers = await getAccounts(hre.network.name);

    const deployerAccount = signers[0];

    const adminAccount = signers[1];
    const adminAccountAddress = await adminAccount.getAddress();

    const poolCreatorAccountAddress = await signers[1].getAddress();

    const poolAdminAccount = adminAccount;
    const poolAdminAccountAddress = adminAccountAddress;

    const poolManagerAccount = signers[1];
    const drawRecipientAccount = signers[1];
    const clearingManagerAccount = signers[1];
    const fundsManagerAccount = signers[1];
    const feeClaimerAccount = signers[1];

    const poolManagerAccountAddress = await poolManagerAccount.getAddress();
    const drawRecipientAccountAddress = await drawRecipientAccount.getAddress();
    const clearingManagerAccountAddress =
        await clearingManagerAccount.getAddress();
    const fundsManagerAccountAddress = await fundsManagerAccount.getAddress();
    const feeClaimerAccountAddress = await feeClaimerAccount.getAddress();

    console.info('admin account address', adminAccountAddress);

    // grant ROLE_LENDING_POOL_CREATOR role to admin
    console.info(`Grant ROLE_LENDING_POOL_CREATOR`, poolCreatorAccountAddress);
    await grantRole(
        poolCreatorAccountAddress,
        ROLE_LENDING_POOL_CREATOR,
        adminAccount,
    );

    // create lending pool
    console.info(`Creating Lending Pool`);
    console.info(`lending pool name: ${poolName}`);
    console.info(`lending pool symbol: ${poolSymbol}`);
    console.info(`number of tranches: ${numberOfTranches}`);

    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses['LendingPoolManager'].address,
        adminAccount,
    );

    // tranche config
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
        poolAdmin: poolAdminAccountAddress, // ROLE_POOL_ADMIN
        drawRecipient: drawRecipientAccountAddress,
        desiredDrawAmount: BigInt(0),
    };
    console.info('Pool Config', createPoolConfig);

    tx = await lendingPoolManagerAdmin.createPool(createPoolConfig);
    const txReceipt = await tx.wait(1);

    // get new lending pool address from event emitted
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
    const lendingPoolAddress = lastEvent.args[1].lendingPool;
    const pendingPoolAddress = lastEvent.args[1].pendingPool;
    const trancheAddresses = lastEvent.args[1].tranches;

    console.info('LendingPool Address:', lendingPoolAddress);
    console.info('PendingPool Address:', pendingPoolAddress);
    console.info('Tranche Addresses"', trancheAddresses);

    // grant lending pool roles to new lending pool
    console.info('Granting roles to lending pool');

    console.info('ROLE_POOL_MANAGER', poolManagerAccountAddress);
    await grantLendingPoolRole(
        lendingPoolAddress,
        poolManagerAccountAddress,
        ROLE_POOL_MANAGER,
        poolAdminAccount,
    );

    console.info('ROLE_POOL_CLEARING_MANAGER', clearingManagerAccountAddress);
    await grantLendingPoolRole(
        lendingPoolAddress,
        clearingManagerAccountAddress,
        ROLE_POOL_CLEARING_MANAGER,
        poolAdminAccount,
    );

    console.info('ROLE_POOL_FUNDS_MANAGER', fundsManagerAccountAddress);
    await grantLendingPoolRole(
        lendingPoolAddress,
        fundsManagerAccountAddress,
        ROLE_POOL_FUNDS_MANAGER,
        poolAdminAccount,
    );

    console.info('ROLE_PROTOCOL_FEE_CLAIMER', feeClaimerAccountAddress);
    await grantLendingPoolRole(
        lendingPoolAddress,
        feeClaimerAccountAddress,
        ROLE_PROTOCOL_FEE_CLAIMER,
        poolAdminAccount,
    );

    return {
        lendingPoolAddress,
        pendingPoolAddress,
        trancheAddresses,
        roles: {
            poolAdminAccount,
            poolManagerAccount,
            drawRecipientAccount,
            clearingManagerAccount,
            fundsManagerAccount,
            feeClaimerAccount,
        },
    };
}
