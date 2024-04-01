import * as addresses from '../deployments/localhost/addresses-localhost.json';
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

async function main() {
    let tx: ContractTransactionResponse;

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
        addresses['USDC'].address,
        adminAccount,
    );

    tx = await usdcAdmin.transfer(aliceAccount, 1000_000_000); // alice: 1000 USDC
    await tx.wait(1);

    tx = await usdcAdmin.transfer(bobAccount, 1000_000_000); // bob: 1000 USDC
    await tx.wait(1);

    // access control
    console.info('Granting ROLE_LENDING_POOL_CREATOR role');
    const kasuControllerAdmin = KasuController__factory.connect(
        addresses['KasuController'].address,
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
        addresses['LendingPoolManager'].address,
        poolCreatorAccount,
    );

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
        drawRecipient: drawRecipientAccount.address,
        desiredDrawAmount: BigInt(100_000_000_000),
    };

    tx = await lendingPoolManagerAdmin.createPool(createPoolConfig);
    await tx.wait(1);

    // get new lending pool address
    console.info('Get new lending pool address');

    const lendingPoolFactory = LendingPoolFactory__factory.connect(
        addresses['LendingPoolFactory'].address,
        adminAccount,
    );

    const allPoolCreatedFilter = lendingPoolFactory.filters.PoolCreated();
    const allPoolCreatedEvents = await lendingPoolFactory.queryFilter(
        allPoolCreatedFilter,
    );

    const lastEvent = allPoolCreatedEvents[allPoolCreatedEvents.length - 1];
    const createdLendingPoolAddress = lastEvent.args[1].lendingPool;
    const createdPendingPoolAddress = lastEvent.args[1].pendingPool;
    const createdTrancheAddresses = lastEvent.args[1].tranches;

    console.info('LendingPool Address:', createdLendingPoolAddress);
    console.info('PendingPool Address:', createdPendingPoolAddress);
    console.info('Tranche Addresses"', createdTrancheAddresses);

    // add users to allow list
    console.info('Add users to allow list');
    const kasuAllowListAdmin = KasuAllowList__factory.connect(
        addresses['KasuAllowList'].address,
        adminAccount,
    );

    tx = await kasuAllowListAdmin.allowUser(aliceAccount);
    await tx.wait(1);

    tx = await kasuAllowListAdmin.allowUser(bobAccount);
    await tx.wait(1);

    // deposit request
    await requestDeposit(
        aliceAccount,
        createdLendingPoolAddress,
        createdTrancheAddresses[0],
        BigInt(350_000_000),
    );

    await requestDeposit(
        bobAccount,
        createdLendingPoolAddress,
        createdTrancheAddresses[1],
        BigInt(100_000_000),
    );
}

async function requestDeposit(
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
