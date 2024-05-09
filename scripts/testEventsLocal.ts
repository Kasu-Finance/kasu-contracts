import * as deployment from '../.openzeppelin/localhost-addresses.json';
import {
    KSU__factory,
    KSULocking__factory,
    MockUSDC__factory,
} from '../typechain-types';
import * as hre from 'hardhat';
import { parseUnits } from 'ethers';
import { lockPeriod30, lockPeriod180 } from './utils/addLockPeriods';

async function main() {
    // contract addresses
    const ksuLockingAddress =
        deployment['KSULocking'].address;
    const ksuAddress = deployment['KSU'].address;
    const usdcAddress = deployment['USDC'].address;

    // signers
    const signers = await hre.ethers.getSigners();
    const admin = signers[0];
    const alice = signers[1];
    const bob = signers[2];

    // contracts
    const ksuAdminContract = KSU__factory.connect(ksuAddress, admin);
    const ksuAliceContract = KSU__factory.connect(ksuAddress, alice);
    const ksuBobContract = KSU__factory.connect(ksuAddress, bob);
    const ksuLockingAdminContract = KSULocking__factory.connect(
        ksuLockingAddress,
        admin,
    );
    const usdcAdminContract = MockUSDC__factory.connect(usdcAddress, admin);

    let tx;

    // mint USDC to admin
    tx = await usdcAdminContract.mint(admin.address, parseUnits('1000', 6));
    await tx.wait();

    // fees emitted
    tx = await usdcAdminContract.approve(
        ksuLockingAddress,
        parseUnits('200', 6),
    );
    await tx.wait();

    tx = await ksuLockingAdminContract.emitFees(parseUnits('200', 6));
    await tx.wait();

    tx = await usdcAdminContract.approve(
        ksuLockingAddress,
        parseUnits('600', 6),
    );
    await tx.wait();

    tx = await ksuLockingAdminContract.emitFees(parseUnits('600', 6));
    await tx.wait();

    // alice locks 50 KSU
    await ksuAdminContract.transfer(alice, parseUnits('100', 'ether'));
    await ksuAliceContract.approve(
        ksuLockingAddress,
        parseUnits('100', 'ether'),
    );
    const ksuLockingContractAlice = KSULocking__factory.connect(
        ksuLockingAddress,
        alice,
    );
    tx = await ksuLockingContractAlice.lock(
        parseUnits('100', 'ether'),
        lockPeriod30,
    );
    await tx.wait();

    // alice locks 800 KSU
    tx = await ksuAdminContract.transfer(alice, parseUnits('800', 'ether'));
    await tx.wait();
    tx = await ksuAliceContract.approve(
        ksuLockingAddress,
        parseUnits('800', 'ether'),
    );
    await tx.wait();

    tx = await ksuLockingContractAlice.lock(
        parseUnits('800', 'ether'),
        lockPeriod180,
    );
    await tx.wait();

    // bob locks 404 KSU
    tx = await ksuAdminContract.transfer(bob, parseUnits('404', 'ether'));
    await tx.wait();
    tx = await ksuBobContract.approve(
        ksuLockingAddress,
        parseUnits('404', 'ether'),
    );
    await tx.wait();

    const ksuLockingContractBob = KSULocking__factory.connect(
        ksuLockingAddress,
        bob,
    );
    tx = await ksuLockingContractBob.lock(
        parseUnits('404', 'ether'),
        lockPeriod30,
    );
    await tx.wait();

    // alice claims fees
    tx = await ksuLockingContractAlice.claimFees();
    await tx.wait();

    // alice unlocks 800 KSU
    // tx = await ksuLockingContractAlice.unlock(parseUnits('50', 'ether'), 0n);
    // await tx.wait();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
