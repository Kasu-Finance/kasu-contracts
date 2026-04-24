import { getChainConfig } from '../_config/chains';

// Shared spec for the April 2026 security upgrade. Imported by:
//   - generateUpgrade2026_04.ts (deploys impls + writes Safe batch)
//   - verifyUpgrade2026_04.ts (re-derives constructor args to verify on the explorer)

export type UpgradeKind = 'proxy' | 'beacon';

export type Deps = {
    addresses: Record<
        string,
        { address: string; implementation?: string; proxyType?: string }
    >;
    chainConfig: ReturnType<typeof getChainConfig>;
};

export type UpgradeSpec = {
    // Key in the network's addresses.json file (e.g. 'SystemVariables', 'UserManager').
    name: string;
    // The Solidity contract to deploy (may differ from `name` in Lite mode — e.g. name
    // 'UserManager' maps to contractName 'UserManagerLite').
    contractName: string;
    // Proxy (TransparentProxy with dedicated ProxyAdmin) vs Beacon (UpgradeableBeacon).
    kind: UpgradeKind;
    // Fully qualified contract source path for `hardhat verify --contract ...`. Only
    // needed when two contracts share a class name (e.g. ProtocolFeeManagerLite which
    // extends FeeManager). Safe to always provide.
    sourcePath: string;
    // Constructor args for the new implementation. Called with the loaded addresses
    // file + chain config so args are chain-specific.
    constructorArgs: (deps: Deps) => unknown[];
};

// Per-chain upgrade list. Order drives the Safe batch ordering — transparent proxies
// first (simpler to reason about), beacons last.
export const UPGRADE_LISTS: Record<string, UpgradeSpec[]> = {
    'xdc-usdc': [
        {
            name: 'SystemVariables',
            contractName: 'SystemVariables',
            sourcePath: 'src/core/SystemVariables.sol:SystemVariables',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.KsuPrice.address,
                d.addresses.KasuController.address,
            ],
        },
        {
            name: 'UserLoyaltyRewards',
            contractName: 'UserLoyaltyRewardsLite',
            sourcePath: 'src/core/UserLoyaltyRewardsLite.sol:UserLoyaltyRewardsLite',
            kind: 'proxy',
            constructorArgs: () => [],
        },
        {
            name: 'PendingPool',
            contractName: 'PendingPool',
            sourcePath: 'src/core/lendingPool/PendingPool.sol:PendingPool',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.USDC.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.UserManager.address,
                d.addresses.ClearingCoordinator.address,
                d.addresses.AcceptedRequestsCalculation.address,
                d.addresses.FixedTermDeposit.address,
            ],
        },
        {
            name: 'LendingPoolTranche',
            contractName: 'LendingPoolTranche',
            sourcePath: 'src/core/lendingPool/LendingPoolTranche.sol:LendingPoolTranche',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.UserManager.address,
                d.addresses.FixedTermDeposit.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.USDC.address,
            ],
        },
    ],
    xdc: [
        {
            name: 'SystemVariables',
            contractName: 'SystemVariables',
            sourcePath: 'src/core/SystemVariables.sol:SystemVariables',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.KsuPrice.address,
                d.addresses.KasuController.address,
            ],
        },
        {
            name: 'UserManager',
            contractName: 'UserManagerLite',
            sourcePath: 'src/core/UserManagerLite.sol:UserManagerLite',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.KSULocking.address,
                d.addresses.UserLoyaltyRewards.address,
            ],
        },
        {
            name: 'UserLoyaltyRewards',
            contractName: 'UserLoyaltyRewardsLite',
            sourcePath: 'src/core/UserLoyaltyRewardsLite.sol:UserLoyaltyRewardsLite',
            kind: 'proxy',
            constructorArgs: () => [],
        },
        {
            name: 'PendingPool',
            contractName: 'PendingPool',
            sourcePath: 'src/core/lendingPool/PendingPool.sol:PendingPool',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.USDC.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.UserManager.address,
                d.addresses.ClearingCoordinator.address,
                d.addresses.AcceptedRequestsCalculation.address,
                d.addresses.FixedTermDeposit.address,
            ],
        },
        {
            name: 'LendingPoolTranche',
            contractName: 'LendingPoolTranche',
            sourcePath: 'src/core/lendingPool/LendingPoolTranche.sol:LendingPoolTranche',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.UserManager.address,
                d.addresses.FixedTermDeposit.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.USDC.address,
            ],
        },
    ],
    // Plume = xdc's five + two pre-existing mismatches (visibility changes from the
    // release-candidate merge that were never shipped to Plume): LendingPoolManager and
    // LendingPoolFactory. Ordering: transparent proxies first, beacons last.
    plume: [
        {
            name: 'SystemVariables',
            contractName: 'SystemVariables',
            sourcePath: 'src/core/SystemVariables.sol:SystemVariables',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.KsuPrice.address,
                d.addresses.KasuController.address,
            ],
        },
        {
            name: 'UserManager',
            contractName: 'UserManagerLite',
            sourcePath: 'src/core/UserManagerLite.sol:UserManagerLite',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.KSULocking.address,
                d.addresses.UserLoyaltyRewards.address,
            ],
        },
        {
            name: 'UserLoyaltyRewards',
            contractName: 'UserLoyaltyRewardsLite',
            sourcePath: 'src/core/UserLoyaltyRewardsLite.sol:UserLoyaltyRewardsLite',
            kind: 'proxy',
            constructorArgs: () => [],
        },
        {
            name: 'LendingPoolManager',
            contractName: 'LendingPoolManager',
            sourcePath: 'src/core/lendingPool/LendingPoolManager.sol:LendingPoolManager',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.FixedTermDeposit.address,
                d.addresses.USDC.address,
                d.addresses.KasuController.address,
                d.chainConfig.wrappedNativeAddress,
                d.addresses.Swapper.address,
            ],
        },
        {
            name: 'LendingPoolFactory',
            contractName: 'LendingPoolFactory',
            sourcePath: 'src/core/lendingPool/LendingPoolFactory.sol:LendingPoolFactory',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.PendingPool.address,
                d.addresses.LendingPool.address,
                d.addresses.LendingPoolTranche.address,
                d.addresses.KasuController.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.SystemVariables.address,
            ],
        },
        {
            name: 'PendingPool',
            contractName: 'PendingPool',
            sourcePath: 'src/core/lendingPool/PendingPool.sol:PendingPool',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.USDC.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.UserManager.address,
                d.addresses.ClearingCoordinator.address,
                d.addresses.AcceptedRequestsCalculation.address,
                d.addresses.FixedTermDeposit.address,
            ],
        },
        {
            name: 'LendingPoolTranche',
            contractName: 'LendingPoolTranche',
            sourcePath: 'src/core/lendingPool/LendingPoolTranche.sol:LendingPoolTranche',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.UserManager.address,
                d.addresses.FixedTermDeposit.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.USDC.address,
            ],
        },
    ],
    // Base (Full deployment). 9 impl upgrades: the April 2026 security set
    // (SystemVariables, UserManager, UserLoyaltyRewards, PendingPool,
    // LendingPoolTranche) plus four pre-existing mismatches that were never shipped
    // to Base from the release-candidate merge / FixedTermDeposit bug fix:
    // KSULocking, LendingPoolManager, FeeManager, FixedTermDeposit. Ordering:
    // transparent proxies first, beacons last. Contract names are Full variants
    // (not *Lite) — Base has the KSU token + loyalty + locking live.
    base: [
        {
            name: 'SystemVariables',
            contractName: 'SystemVariables',
            sourcePath: 'src/core/SystemVariables.sol:SystemVariables',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.KsuPrice.address,
                d.addresses.KasuController.address,
            ],
        },
        {
            name: 'UserManager',
            contractName: 'UserManager',
            sourcePath: 'src/core/UserManager.sol:UserManager',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.KSULocking.address,
                d.addresses.UserLoyaltyRewards.address,
            ],
        },
        {
            name: 'UserLoyaltyRewards',
            contractName: 'UserLoyaltyRewards',
            sourcePath: 'src/core/UserLoyaltyRewards.sol:UserLoyaltyRewards',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.KsuPrice.address,
                d.addresses.KSU.address,
                d.addresses.KasuController.address,
            ],
        },
        {
            name: 'KSULocking',
            contractName: 'KSULocking',
            sourcePath: 'src/locking/KSULocking.sol:KSULocking',
            kind: 'proxy',
            constructorArgs: (d) => [d.addresses.KasuController.address],
        },
        {
            name: 'LendingPoolManager',
            contractName: 'LendingPoolManager',
            sourcePath: 'src/core/lendingPool/LendingPoolManager.sol:LendingPoolManager',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.FixedTermDeposit.address,
                d.addresses.USDC.address,
                d.addresses.KasuController.address,
                d.chainConfig.wrappedNativeAddress,
                d.addresses.Swapper.address,
            ],
        },
        {
            name: 'FeeManager',
            contractName: 'FeeManager',
            sourcePath: 'src/core/FeeManager.sol:FeeManager',
            kind: 'proxy',
            constructorArgs: (d) => [
                d.addresses.USDC.address,
                d.addresses.SystemVariables.address,
                d.addresses.KasuController.address,
                d.addresses.KSULocking.address,
                d.addresses.LendingPoolManager.address,
            ],
        },
        {
            name: 'FixedTermDeposit',
            contractName: 'FixedTermDeposit',
            sourcePath: 'src/core/lendingPool/FixedTermDeposit.sol:FixedTermDeposit',
            kind: 'proxy',
            constructorArgs: (d) => [d.addresses.SystemVariables.address],
        },
        {
            name: 'PendingPool',
            contractName: 'PendingPool',
            sourcePath: 'src/core/lendingPool/PendingPool.sol:PendingPool',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.SystemVariables.address,
                d.addresses.USDC.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.UserManager.address,
                d.addresses.ClearingCoordinator.address,
                d.addresses.AcceptedRequestsCalculation.address,
                d.addresses.FixedTermDeposit.address,
            ],
        },
        {
            name: 'LendingPoolTranche',
            contractName: 'LendingPoolTranche',
            sourcePath: 'src/core/lendingPool/LendingPoolTranche.sol:LendingPoolTranche',
            kind: 'beacon',
            constructorArgs: (d) => [
                d.addresses.UserManager.address,
                d.addresses.FixedTermDeposit.address,
                d.addresses.LendingPoolManager.address,
                d.addresses.USDC.address,
            ],
        },
    ],
};

// Post-upgrade calls appended to the Safe batch after all impl upgrades.
// Currently only Base needs one — seeding UserLoyaltyRewards reward caps so the
// FV-01 RewardCapsNotSet guard doesn't block the first loyalty batch emission
// whenever the KSU token and weekly emission cron go live.

const SET_REWARD_CAPS_ABI = {
    inputs: [
        { internalType: 'uint256', name: 'perUser', type: 'uint256' },
        { internalType: 'uint256', name: 'perBatch', type: 'uint256' },
    ],
    name: 'setRewardCaps',
    payable: false,
};

export type PostUpgradeTx = {
    to: string;
    value: string;
    data: null;
    contractMethod: typeof SET_REWARD_CAPS_ABI;
    contractInputsValues: Record<string, string>;
    _note?: string;
};

export const POST_UPGRADE_TXS: Record<string, (d: Deps) => PostUpgradeTx[]> = {
    base: (d) => {
        const oneThousandKsu = (1_000n * 10n ** 18n).toString();
        return [
            {
                to: d.addresses.UserLoyaltyRewards.address,
                value: '0',
                data: null,
                contractMethod: SET_REWARD_CAPS_ABI,
                contractInputsValues: {
                    perUser: oneThousandKsu,
                    perBatch: oneThousandKsu,
                },
                _note:
                    'UserLoyaltyRewards.setRewardCaps(1_000e18, 1_000e18) — seeds conservative ' +
                    'initial caps so the first real emission (at KSU launch) does not revert with ' +
                    'RewardCapsNotSet. Retune post-launch from observed emission volume.',
            },
        ];
    },
};
