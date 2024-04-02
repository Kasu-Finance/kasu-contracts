import path from 'path';
import fs from 'fs';
import {
    KasuAllowList__factory,
    KasuController__factory,
    LendingPoolFactory__factory,
    LendingPoolManager__factory,
    MockUSDC__factory,
} from '../typechain-types';
import * as hre from 'hardhat';
import {
    CreatePoolConfigStruct,
    CreateTrancheConfigStruct,
} from '../typechain-types/src/core/lendingPool/LendingPool';
import { ContractTransactionResponse, Signer } from 'ethers';

const POOL_CLEARING_MANAGER_PK = "";
// address: 0x97cbcD33f1075070e59F354E4eCf71Ed6267E1ED

async function main() {
    let tx: ContractTransactionResponse;

    const deploymentAddressesPath = path.join(`./deployments/${hre.network.name}/addresses-${hre.network.name}.json`);
    const deploymentAddresses = JSON.parse((fs.readFileSync(deploymentAddressesPath)).toString());

    const clearingManager = new hre.ethers.Wallet(POOL_CLEARING_MANAGER_PK, hre.ethers.provider);

    // signers
    const namedSigners = await hre.ethers.getNamedSigners();
    const adminAccount = namedSigners['admin'];
    const aliceAccount = namedSigners['alice'];
    const bobAccount = namedSigners['bob'];

    const unNamedSigners = await hre.ethers.getUnnamedSigners();
    const poolCreatorAccount = unNamedSigners[0];
    const poolAdminAccount = unNamedSigners[1];
    const drawRecipientAccount = unNamedSigners[2];

    // fund accounts
    console.info('Finding accounts with USDC');

    const usdcAdmin = MockUSDC__factory.connect(
        deploymentAddresses['USDC'].address,
        adminAccount,
    );

    tx = await usdcAdmin.transfer(aliceAccount, 2000_000_000); // alice: 1000 USDC
    await tx.wait(1);

    tx = await usdcAdmin.transfer(bobAccount, 2000_000_000); // bob: 1000 USDC
    await tx.wait(1);

    // access control
    console.info('Granting ROLE_LENDING_POOL_CREATOR role');
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
    console.info('Creating Lending Pool');

    const lendingPoolManagerAdmin = LendingPoolManager__factory.connect(
        deploymentAddresses['LendingPoolManager'].address,
        poolCreatorAccount,
    );

    const juniorTrancheConfig: CreateTrancheConfigStruct = {
        ratio: 20_00, // 20%
        interestRate: 2500000000000000, // 10%
        minDepositAmount: 500_000_000, // 500 USDC
        maxDepositAmount: 3000_000_000, // 3000 USDC
    };
    const mezzoTrancheConfig: CreateTrancheConfigStruct = {
        ratio: 30_00,
        interestRate: 2000000000000000,
        minDepositAmount: 100_000_000,
        maxDepositAmount: 10_000_000_000,
    };
    const seniorTrancheConfig: CreateTrancheConfigStruct = {
        ratio: 50_00,
        interestRate: 1500000000000000,
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
        drawRecipient: drawRecipientAccount.address,
        desiredDrawAmount: BigInt(0),
    };

    tx = await lendingPoolManagerAdmin.createPool(createPoolConfig);
    const txReceipt = await tx.wait(1);

    // get new lending pool address
    console.info('Get new lending pool address');

    const lendingPoolFactory = LendingPoolFactory__factory.connect(
        deploymentAddresses['LendingPoolFactory'].address,
        adminAccount,
    );

    const allPoolCreatedFilter = lendingPoolFactory.filters.PoolCreated();
    const allPoolCreatedEvents = await lendingPoolFactory.queryFilter(
        allPoolCreatedFilter,
        txReceipt ? txReceipt.blockNumber : undefined
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
    tx = await kasuControllerAdmin.connect(poolAdminAccount).grantLendingPoolRole(
        createdLendingPoolAddress,
        ROLE_POOL_CLEARING_MANAGER,
        clearingManager.address,
    );
    await tx.wait(1);

    // add users to allow list
    console.info('Add users to allow list');
    const kasuAllowListAdmin = KasuAllowList__factory.connect(
        deploymentAddresses['KasuAllowList'].address,
        adminAccount,
    );

    tx = await kasuAllowListAdmin.allowUser(aliceAccount);
    await tx.wait(1);

    tx = await kasuAllowListAdmin.allowUser(bobAccount);
    await tx.wait(1);

    // deposit request
    await requestDeposit(
        deploymentAddresses,
        aliceAccount,
        createdLendingPoolAddress,
        createdTrancheAddresses[2],
        BigInt(2000_000_001),
    );

    await requestDeposit(
        deploymentAddresses,
        bobAccount,
        createdLendingPoolAddress,
        createdTrancheAddresses[2],
        BigInt(1000_000_001),
    );
}

async function requestDeposit(
    addresses: any,
    requester: Signer,
    lendingPoolAddress: string,
    trancheAddress: string,
    amount: bigint,
) {
    let tx: ContractTransactionResponse;

    console.info('User deposit request');
    const usdcUser = MockUSDC__factory.connect(
        addresses['USDC'].address,
        requester,
    );

    tx = await usdcUser.approve(
        addresses['LendingPoolManager'].address,
        amount,
    );
    await tx.wait(1);

    const lendingPoolManagerAlice = LendingPoolManager__factory.connect(
        addresses['LendingPoolManager'].address,
        requester,
    );
    tx = await lendingPoolManagerAlice.requestDeposit(
        lendingPoolAddress,
        trancheAddress,
        amount,
    );
    await tx.wait(1);
    return tx;
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
