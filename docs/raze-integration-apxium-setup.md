# Apxium setup: Raze vault integration (xdc-usdc)

On-chain steps to onboard the Raze vault as a whitelisted FixedTermDeposit depositor on the three USDC pools of the `xdc-usdc` deployment (chainId 50).

## Contracts

| Contract              | Address                                      |
| --------------------- | -------------------------------------------- |
| `LendingPoolManager`  | `0x5ba223175F61221fbc795F71a41f52Bff825C68b` |
| `FixedTermDeposit`    | `0x3f0685e6B1aD224D9b780Ff5E7230Ff021EfF9f0` |
| `KasuAllowList`       | `0xaf911547FD38686a88fc26B2A722F870426bCD6D` |
| `KasuController`      | `0xe76eE99fC85531857B9011C1D4223C7D1B591D60` |

## Callers

- **Pool Admin Multisig** (`ROLE_LENDING_POOL_CREATOR`, `ROLE_POOL_ADMIN`): `0x880Aa2d6eEC5bD573059444cF1b3C09658f8c112`
- **Pool Manager Multisig** (`ROLE_POOL_MANAGER`): `0x21567eA21b14BEd14657e9725C2FE11C7be942B1`
- **Kasu Multisig** (`ROLE_KASU_ADMIN`): `0x1E9ed74140DA7B81a1612AA5df33F98Eb5Ea0B4D` — **not Apxium**. Kasu executes the allowlist step itself; listed here for completeness.

## ⚠️ Safe template sanity check

When the Apxium pool admin multisig set up XDC AUDD pools, 3 role-grant txns targeted a stale EOA (`0x7923...f693`) instead of `KasuController`. Calls succeeded silently as no-ops. **Before submitting any of the calls below, confirm each `to` field is one of the three contracts in the table above.**

---

## Steps

### 1. Create 3 USDC pools — Pool Admin Multisig

Target: `LendingPoolManager`

```solidity
createPool(CreatePoolConfig calldata createPoolConfig) external returns (LendingPoolDeployment);
```

Three calls, one per pool, using the strategy configs Apxium already uses for USDC. Capture each returned `lendingPool` + `tranche` address from events — they're the inputs to step 2.

### 2. Add one FixedTermDeposit config per pool — Pool Manager Multisig

Target: `LendingPoolManager`

```solidity
addLendingPoolTrancheFixedTermDeposit(
    address lendingPool,
    address tranche,
    uint256 epochLockDuration,   // TBD — 26 or 52 per pool
    uint256 epochInterestRate,   // TBD per pool (100% == 1e18)
    bool    whitelistedOnly      // = true
);
```

Three calls, one per pool. Capture the returned `fixedTermConfigId` for each (should be `1` per pool since these are the first configs). Emits `LendingPoolTrancheFixedTermDepositConfigAdded`.

### 3. Whitelist the Raze vault on each FT config — Pool Manager Multisig

Target: `LendingPoolManager`

```solidity
updateFixedTermDepositAllowlist(
    address lendingPool,
    uint256 configId,                    // from step 2
    address[] calldata users,            // = [RAZE_VAULT_ADDRESS]
    bool[]    calldata isAllowedList     // = [true]
);
```

Three calls, one per `(pool, configId)` pair.

### 4. Set withdrawal window per pool — Pool Manager Multisig

Target: `LendingPoolManager`

```solidity
updateLendingPoolWithdrawalConfiguration(
    address lendingPool,
    LendingPoolWithdrawalConfiguration { uint128 requestEpochsInAdvance; uint128 cancelRequestEpochsInAdvance; }
);
```

**Goal:** shortest possible window so principal is released in the unlock epoch's clearing. Suggested values: `requestEpochsInAdvance = 1`, `cancelRequestEpochsInAdvance = 0` (must satisfy `cancelRequestEpochsInAdvance ≤ requestEpochsInAdvance`). Three calls, one per pool.

### 5. Allowlist the Raze vault for deposits — Kasu Multisig (not Apxium)

Target: `KasuAllowList`

```solidity
allowUser(address user);   // user = RAZE_VAULT_ADDRESS
```

One call. Required because `LendingPoolManager.requestDeposit` gates `msg.sender` on `isUserAllowed`.

---

## Order

Steps 1 → 2 → 3 → 4 can run in a single Apxium Safe batch per pool (or one batch with all pools). Step 5 is Kasu-side; can run in parallel or before any of 1–4.

## Verification

After execution, confirm for each pool:

- `FixedTermDeposit.lendingPoolFixedTermDepositConfigCount(pool) == 1`
- `FixedTermDeposit.fixedTermDepositsAllowlist(pool, 1, RAZE_VAULT) == true`
- `KasuAllowList.allowList(RAZE_VAULT) == true`
