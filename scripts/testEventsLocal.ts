import * as deployment from '../deployments/localhost/export.json';
import { KSU__factory, KSULocking__factory } from '../typechain-types';
import * as hre from 'hardhat';
import { parseUnits } from 'ethers';
import { lockPeriod180, lockPeriod30 } from '../deploy/deploy';

async function main() {
    // contract addresses
    const ksuLockingAddress =
        deployment['31337'][0]['contracts']['KSULocking'].address;
    const ksuAddress = deployment['31337'][0]['contracts']['KSU'].address;
    const usdcAddress = deployment['31337'][0]['contracts']['MockUSDC'].address;
    // signers
    const namedSigners = await hre.ethers.getNamedSigners();
    const admin = namedSigners['admin'];
    const alice = namedSigners['alice'];
    const bob = namedSigners['bob'];
    // contracts
    const ksuAdminContract = KSU__factory.connect(ksuAddress, admin);
    const ksuAliceContract = KSU__factory.connect(ksuAddress, alice);
    const ksuBobContract = KSU__factory.connect(ksuAddress, bob);
    const ksuLockingAdminContract = KSULocking__factory.connect(
        ksuLockingAddress,
        admin,
    );
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
    await ksuLockingContractAlice.lock(
        parseUnits('100', 'ether'),
        lockPeriod30,
    );
    // alice locks 800 KSU
    await ksuAdminContract.transfer(alice, parseUnits('800', 'ether'));
    await ksuAliceContract.approve(
        ksuLockingAddress,
        parseUnits('800', 'ether'),
    );
    await ksuLockingContractAlice.lock(
        parseUnits('800', 'ether'),
        lockPeriod180,
    );
    // bob locks 404 KSU
    await ksuAdminContract.transfer(bob, parseUnits('404', 'ether'));
    await ksuBobContract.approve(ksuLockingAddress, parseUnits('404', 'ether'));
    const ksuLockingContractBob = KSULocking__factory.connect(
        ksuLockingAddress,
        bob,
    );
    await ksuLockingContractBob.lock(parseUnits('404', 'ether'), lockPeriod30);
    // fees emitted
    await ksuLockingAdminContract.emitFees(parseUnits('200', 6));
    await ksuLockingAdminContract.emitFees(parseUnits('600', 6));
    // alice unlocks 800 KSU
    await ksuLockingContractAlice.unlock(parseUnits('50', 'ether'), 0n);
    // alice claims fees
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
