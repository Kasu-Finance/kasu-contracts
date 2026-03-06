# Contract Changes: Per-Asset Sub-Pool Support

## Change Summary

| Contract | Proxy Type | Change Level | Key Changes |
|----------|-----------|-------------|-------------|
| `LendingPoolManager` | TransparentProxy | Medium | New deposit/repay/draw entry points for additional assets |
| `PendingPool` | BeaconProxy | High | Per-asset deposit NFT tracking, per-asset pending totals, modified accept/reject/cancel |
| `LendingPool` | BeaconProxy | High | Per-asset LP balances, owed amounts, interest, draw/repay |
| `LendingPoolTranche` | BeaconProxy | High | Per-asset share tracking parallel to ERC4626 |
| `ClearingCoordinator` | TransparentProxy | Medium | Per-asset clearing orchestration |
| `FeeManager` | TransparentProxy | Low-Medium | Per-asset fee collection |
| `PendingRequestsPriorityCalculation` | (part of PendingPool) | Medium | Per-asset deposit/withdrawal aggregation |
| `AcceptedRequestsExecution` | (part of PendingPool) | Medium | Asset-aware request execution |
| `AcceptedRequestsCalculation` | TransparentProxy | **None** | Pure function, called per-asset with per-asset inputs |
| `LendingPoolFactory` | TransparentProxy | **None** | Pool creation unchanged |
| `LendingPoolTrancheLoss` | (part of Tranche) | Low | Per-asset loss tracking (if needed) |
| `FixedTermDeposit` | TransparentProxy | Medium | Per-asset fixed term lock tracking |
| `UserManager` | TransparentProxy | **None** | Loyalty is per-user, not per-asset |
| `UserLoyaltyRewards` | TransparentProxy | **None** | Rewards calculation unchanged |
| `KSULocking` / `rKSU` | TransparentProxy | **None** | Fee distribution may stay base-asset only |
| `KasuAllowList` | TransparentProxy | **None** | KYC is per-user, not per-asset |
| `SystemVariables` | TransparentProxy | **None** | Epoch/interest config unchanged |
| `Swapper` / `DepositSwap` | N/A | **None** | Swap infrastructure unchanged |

## Detailed Changes Per Contract

---

### 1. PendingPool (BeaconProxy) — MOST IMPACTED

**File**: `src/core/lendingPool/PendingPool.sol`

#### New Storage Variables (appended after existing — safe for proxy upgrade)

```solidity
/// @dev Tracks which asset each deposit NFT was made in.
/// address(0) = base asset (for backwards compatibility with pre-upgrade NFTs).
mapping(uint256 dNftID => address) private _depositAsset;

/// @dev Per-asset total pending deposit amount (parallel to totalPendingDepositAmount).
mapping(address asset => uint256) public totalPendingDepositAmountPerAsset;

/// @dev Per-asset per-epoch pending deposit amount (parallel to _totalEpochPendingDepositAmount).
mapping(address asset => mapping(uint256 epoch => uint256)) private _totalEpochPendingDepositAmountPerAsset;

/// @dev Per-asset per-user per-tranche pending deposit amount.
mapping(address asset => mapping(address user => mapping(address tranche => uint256)))
    private _totalUserTranchePendingDepositAmountPerAsset;

/// @dev Tracks which asset each withdrawal NFT is for.
/// address(0) = base asset.
mapping(uint256 wNftID => address) private _withdrawalAsset;
```

#### New Methods

```solidity
/// @notice Creates a pending deposit for an additional asset.
/// @dev Called by LendingPoolManager. Transfers the additional asset from caller.
function requestDepositInAsset(
    address user,
    address tranche,
    address asset,
    uint256 amount,
    uint256 fixedTermConfigId
) external onlyLendingPoolManager returns (uint256 dNftID);

/// @notice Creates a pending withdrawal for a specific asset.
/// @dev The asset must match what the user deposited in that tranche.
function requestWithdrawalInAsset(
    address user,
    address tranche,
    address asset,
    uint256 sharesToWithdraw
) external onlyLendingPoolManager returns (uint256 wNftID);

/// @notice Returns the asset associated with a deposit NFT.
function depositNftAsset(uint256 dNftID) external view returns (address);

/// @notice Returns the asset associated with a withdrawal NFT.
function withdrawalNftAsset(uint256 wNftID) external view returns (address);

/// @notice Per-asset pending deposit amount for current epoch.
function pendingDepositAmountForCurrentEpochPerAsset(address asset) external view returns (uint256);
```

#### Modified Internal Methods

**`requestDepositInAsset()`** — new method, mirrors `requestDeposit()`:
- Uses `IERC20(asset).safeTransferFrom(msg.sender, address(this), amount)` instead of `_transferAssetsFrom`
- Sets `_depositAsset[dNftID] = asset`
- Updates per-asset pending totals instead of (or in addition to) global totals

**`_acceptDepositRequest()`** (line 595) — modified to be asset-aware:
```solidity
address asset = _depositAsset[dNftID]; // address(0) = base asset
if (asset == address(0)) {
    // Existing base asset flow (unchanged)
    _approveAsset(address(lendingPool), acceptedAmount);
    trancheSharesMinted = lendingPool.acceptDeposit(tranche, user, acceptedAmount);
} else {
    // Additional asset flow
    IERC20(asset).safeIncreaseAllowance(address(lendingPool), acceptedAmount);
    trancheSharesMinted = lendingPool.acceptDepositInAsset(tranche, user, acceptedAmount, asset);
}
```

**`_returnDepositRequest()`** (line 651) — modified for correct asset return:
```solidity
address asset = _depositAsset[dNftID];
if (asset == address(0)) {
    _transferAssets(user, assetAmount); // existing base asset
} else {
    IERC20(asset).safeTransfer(user, assetAmount); // additional asset
    // Clean up per-asset tracking
}
```

**`cancelDepositRequest()`** (line 313) — calls `_returnDepositRequest` which handles asset routing.

**`_acceptWithdrawalRequest()`** (line 667) — modified:
```solidity
address asset = _withdrawalAsset[wNftID];
if (asset == address(0)) {
    // Existing flow
    lendingPool.acceptWithdrawal(tranche, user, acceptedShares);
} else {
    lendingPool.acceptWithdrawalInAsset(tranche, user, acceptedShares, asset);
}
```

#### Impact on PendingRequestsPriorityCalculation

**File**: `src/core/clearing/PendingRequestsPriorityCalculation.sol`

The `calculatePendingRequestsPriorityBatch()` method (line 79) iterates over all pending NFTs and aggregates amounts into `clearingData.pendingDeposits`. Currently:

```solidity
// Line 128-131: aggregates ALL deposits into single totals
clearingData.pendingDeposits.totalDepositAmount += depositNftDetails.assetAmount;
clearingData.pendingDeposits.trancheDepositsAmounts[trancheIndex] += depositNftDetails.assetAmount;
clearingData.pendingDeposits.tranchePriorityDepositsAmounts[trancheIndex][ownerLoyaltyLevel] += depositNftDetails.assetAmount;
```

**Change needed**: Per-asset clearing data. Two approaches:

**Option A — Per-asset ClearingData storage:**
```solidity
// New: per-asset clearing data
mapping(uint256 epoch => mapping(address asset => ClearingData)) private _clearingDataPerEpochPerAsset;
```
Priority calculation checks each NFT's asset and aggregates into the correct per-asset ClearingData.

**Option B — Filter by asset at clearing time:**
The ClearingCoordinator calls priority calculation once per asset, and the batch method filters NFTs by asset. This avoids duplicating storage but requires multiple passes.

**Recommended: Option A** — single pass, per-asset aggregation. More storage but fewer gas-heavy iterations.

#### Impact on AcceptedRequestsExecution

**File**: `src/core/clearing/AcceptedRequestsExecution.sol`

`executeAcceptedRequestsBatch()` (line 57) iterates over pending NFTs and calls `_acceptDepositRequest` / `_acceptWithdrawalRequest`. These internal methods are already modified (above) to be asset-aware.

**Additional change**: The execution batch must use per-asset `ClearingData` for accepted amounts:
```solidity
// Current (line 106):
// Uses clearingData.tranchePriorityDepositsAccepted[trancheIndex][priority]

// New: uses per-asset clearing data
address asset = _depositAsset[dNftID];
ClearingData storage assetClearingData = _clearingDataPerEpochPerAsset[targetEpoch][asset];
// ... use assetClearingData.tranchePriorityDepositsAccepted[trancheIndex][priority]
```

---

### 2. LendingPool (BeaconProxy) — SIGNIFICANT CHANGES

**File**: `src/core/lendingPool/LendingPool.sol`

#### New Storage Variables (appended)

```solidity
/// @dev Per-asset total supply (parallel to ERC20 totalSupply for base asset).
/// Represents total LP value denominated in each additional asset.
mapping(address asset => uint256) public totalSupplyPerAsset;

/// @dev Per-asset tranche balance (parallel to ERC20 balanceOf(tranche) for base asset).
mapping(address asset => mapping(address tranche => uint256)) public trancheBalancePerAsset;

/// @dev Per-asset user owed amount.
mapping(address asset => uint256) public userOwedAmountPerAsset;

/// @dev Per-asset fees owed amount.
mapping(address asset => uint256) public feesOwedAmountPerAsset;

/// @dev Per-asset first loss capital.
mapping(address asset => uint256) public firstLossCapitalPerAsset;

/// @dev List of additional assets this pool holds (for iteration).
address[] private _additionalAssets;

/// @dev Quick lookup for additional assets.
mapping(address asset => bool) private _isAdditionalAsset;
```

#### New Methods

```solidity
/// @notice Accepts deposit of an additional asset.
/// @dev Called by PendingPool during clearing step 4.
function acceptDepositInAsset(address tranche, address user, uint256 acceptedAmount, address asset)
    external onlyPendingPool verifyTranche(tranche) lendingPoolShouldNotBeStopped
    returns (uint256 trancheSharesMinted)
{
    IERC20(asset).safeTransferFrom(msg.sender, address(this), acceptedAmount);
    _trackAdditionalAsset(asset);
    totalSupplyPerAsset[asset] += acceptedAmount;
    trancheBalancePerAsset[asset][tranche] += acceptedAmount;
    trancheSharesMinted = ILendingPoolTranche(tranche).depositInAsset(acceptedAmount, user, asset);
}

/// @notice Accepts withdrawal in an additional asset.
function acceptWithdrawalInAsset(address tranche, address user, uint256 acceptedShares, address asset)
    external onlyPendingPool verifyTranche(tranche)
    returns (uint256 assetAmount)
{
    assetAmount = ILendingPoolTranche(tranche).redeemInAsset(acceptedShares, address(this), msg.sender, asset);
    ILendingPoolTranche(tranche).removeUserActiveSharesPerAsset(user, acceptedShares, asset);
    totalSupplyPerAsset[asset] -= assetAmount;
    trancheBalancePerAsset[asset][tranche] -= assetAmount;
    IERC20(asset).safeTransfer(user, assetAmount);
}

/// @notice Draws funds in an additional asset.
function drawFundsInAsset(uint256 drawAmount, address asset) external onlyClearingCoordinator {
    uint256 available = availableFundsPerAsset(asset);
    require(available >= drawAmount, "insufficient asset");
    userOwedAmountPerAsset[asset] += drawAmount;
    IERC20(asset).safeTransfer(_poolConfiguration.drawRecipient, drawAmount);
}

/// @notice Repays owed funds in an additional asset.
function repayOwedFundsInAsset(uint256 amount, address asset) external onlyLendingPoolManager {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    uint256 feesPaid = _payFeesPerAsset(amount, asset);
    uint256 userRepaid = amount - feesPaid;
    userOwedAmountPerAsset[asset] -= userRepaid;
}

/// @notice Returns available funds for a specific additional asset.
function availableFundsPerAsset(address asset) public view returns (uint256) {
    return totalSupplyPerAsset[asset] - userOwedAmountPerAsset[asset];
}

/// @notice Applies interest for an additional asset.
function applyInterestsPerAsset(uint256 epoch, address asset) external onlyClearingCoordinator {
    for (uint256 i; i < _lendingPoolInfo.trancheAddresses.length; ++i) {
        _applyTrancheInterestPerAsset(_lendingPoolInfo.trancheAddresses[i], epoch, asset);
    }
}

/// @notice Deposits first loss capital in an additional asset.
function depositFirstLossCapitalInAsset(uint256 amount, address asset)
    external onlyLendingPoolManager lendingPoolShouldNotBeStopped
{
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    totalSupplyPerAsset[asset] += amount;
    firstLossCapitalPerAsset[asset] += amount;
}

/// @notice Force immediate withdrawal in a specific asset.
function forceImmediateWithdrawalInAsset(address tranche, address user, uint256 shares, address asset)
    external onlyLendingPoolManager verifyTranche(tranche) verifyClearingNotPending
    returns (uint256 assetAmount)
{
    assetAmount = ILendingPoolTranche(tranche).redeemInAsset(shares, address(this), user, asset);
    ILendingPoolTranche(tranche).removeUserActiveSharesPerAsset(user, shares, asset);
    totalSupplyPerAsset[asset] -= assetAmount;
    trancheBalancePerAsset[asset][tranche] -= assetAmount;
    IERC20(asset).safeTransfer(user, assetAmount);
}
```

#### New Internal Methods

```solidity
/// @dev Applies tranche interest for an additional asset.
function _applyTrancheInterestPerAsset(address tranche, uint256 epoch, address asset) internal {
    uint256 trancheBalance = trancheBalancePerAsset[asset][tranche];
    if (trancheBalance == 0) return;

    uint256 interestAmount = trancheBalance
        * _trancheConfigurationStorage(tranche).interestRate / INTEREST_RATE_FULL_PERCENT;

    uint256 feesAmount = interestAmount * _systemVariables.performanceFee() / FULL_PERCENT;
    uint256 userInterestAmount = interestAmount - feesAmount;

    feesOwedAmountPerAsset[asset] += feesAmount;
    userOwedAmountPerAsset[asset] += userInterestAmount;

    // Update per-asset tranche balance (parallel to _mint for base asset)
    trancheBalancePerAsset[asset][tranche] += userInterestAmount;
    totalSupplyPerAsset[asset] += userInterestAmount;

    // Update tranche's per-asset share ratio
    ILendingPoolTranche(tranche).applyInterestPerAsset(userInterestAmount, asset);
}

/// @dev Pays fees in an additional asset.
function _payFeesPerAsset(uint256 amount, address asset) private returns (uint256 feesPaid) {
    if (amount == 0 || feesOwedAmountPerAsset[asset] == 0) return 0;
    feesPaid = amount > feesOwedAmountPerAsset[asset] ? feesOwedAmountPerAsset[asset] : amount;
    feesOwedAmountPerAsset[asset] -= feesPaid;
    IERC20(asset).safeIncreaseAllowance(address(_feeManager), feesPaid);
    _feeManager.emitFeesInAsset(feesPaid, asset);
}

/// @dev Tracks an additional asset if not already tracked.
function _trackAdditionalAsset(address asset) private {
    if (!_isAdditionalAsset[asset]) {
        _isAdditionalAsset[asset] = true;
        _additionalAssets.push(asset);
    }
}
```

#### Existing Methods — UNCHANGED

All existing methods (`acceptDeposit`, `acceptWithdrawal`, `drawFunds`, `repayOwedFunds`, `applyInterests`, `availableFunds`, `depositFirstLossCapital`, `forceImmediateWithdrawal`, `stop`, `payOwedFees`) continue to operate on the base asset via the existing `_underlyingAsset` immutable. No signature or behavior changes.

---

### 3. LendingPoolTranche (BeaconProxy) — SIGNIFICANT CHANGES

**File**: `src/core/lendingPool/LendingPoolTranche.sol`

The ERC4626 vault continues to handle base-asset shares. Additional assets use parallel storage.

#### New Storage Variables (appended)

```solidity
/// @dev Per-asset total shares (parallel to ERC20 totalSupply for base asset).
mapping(address asset => uint256) public totalSharesPerAsset;

/// @dev Per-asset user shares (parallel to ERC20 balanceOf for base asset).
mapping(address asset => mapping(address user => uint256)) public userSharesPerAsset;

/// @dev Per-asset user active shares (parallel to userActiveShares for base asset).
mapping(address asset => mapping(address user => uint256)) public userActiveSharesPerAsset;

/// @dev Per-asset total assets backing the shares.
/// This tracks the total asset value in the tranche for each additional asset.
mapping(address asset => uint256) public totalAssetsPerAsset;
```

#### New Methods

```solidity
/// @notice Deposits additional asset into the tranche.
/// @dev Mirrors ERC4626 deposit logic but for per-asset tracking.
/// Called by LendingPool.acceptDepositInAsset().
function depositInAsset(uint256 assets, address receiver, address asset)
    external onlyOwnLendingPool notPendingLossMint
    returns (uint256 shares)
{
    // Calculate shares using same ratio as ERC4626:
    // shares = assets * totalShares / totalAssets (with offset for precision)
    shares = _convertToSharesPerAsset(assets, asset);

    totalAssetsPerAsset[asset] += assets;
    totalSharesPerAsset[asset] += shares;

    if (userActiveSharesPerAsset[asset][receiver] == 0) {
        _userManager.addUserActiveTranche(receiver, address(_ownLendingPool()));
    }
    userSharesPerAsset[asset][receiver] += shares;
    userActiveSharesPerAsset[asset][receiver] += shares;
}

/// @notice Redeems additional asset shares from the tranche.
function redeemInAsset(uint256 shares, address receiver, address owner, address asset)
    external onlyOwnLendingPool notPendingLossMint
    returns (uint256 assets)
{
    assets = _convertToAssetsPerAsset(shares, asset);

    userSharesPerAsset[asset][owner] -= shares;
    totalSharesPerAsset[asset] -= shares;
    totalAssetsPerAsset[asset] -= assets;
}

/// @notice Removes user active shares for an additional asset.
function removeUserActiveSharesPerAsset(address user, uint256 shares, address asset)
    external onlyOwnLendingPool
{
    userActiveSharesPerAsset[asset][user] -= shares;
    // Note: user removal from _trancheUsers array should consider
    // both base and additional asset shares before removing
}

/// @notice Applies interest for an additional asset (updates asset backing).
function applyInterestPerAsset(uint256 interestAmount, address asset) external onlyOwnLendingPool {
    totalAssetsPerAsset[asset] += interestAmount;
    // Shares stay the same — each share is now worth more assets
}

/// @notice Returns user active assets for a specific additional asset.
function userActiveAssetsPerAsset(address user, address asset) external view returns (uint256) {
    return _convertToAssetsPerAsset(userActiveSharesPerAsset[asset][user], asset);
}

/// @notice Converts shares to assets for an additional asset.
function convertToAssetsPerAsset(uint256 shares, address asset) external view returns (uint256) {
    return _convertToAssetsPerAsset(shares, asset);
}
```

#### New Internal Methods

```solidity
/// @dev Converts assets to shares for an additional asset.
/// Mirrors OpenZeppelin ERC4626._convertToShares with decimalsOffset.
function _convertToSharesPerAsset(uint256 assets, address asset) internal view returns (uint256) {
    uint256 totalShares = totalSharesPerAsset[asset];
    uint256 totalAssets_ = totalAssetsPerAsset[asset];
    if (totalShares == 0) {
        // First deposit: apply same offset as base asset (10^12)
        return assets * (10 ** _decimalsOffset());
    }
    return assets * totalShares / totalAssets_;
}

/// @dev Converts shares to assets for an additional asset.
function _convertToAssetsPerAsset(uint256 shares, address asset) internal view returns (uint256) {
    uint256 totalShares = totalSharesPerAsset[asset];
    uint256 totalAssets_ = totalAssetsPerAsset[asset];
    if (totalShares == 0) return 0;
    return shares * totalAssets_ / totalShares;
}
```

#### Impact on LendingPoolTrancheLoss

Per-asset loss tracking is needed if impairments should apply per-asset. For initial implementation, losses can apply proportionally across all assets. A per-asset loss system can be added later.

---

### 4. LendingPoolManager (TransparentProxy)

**File**: `src/core/lendingPool/LendingPoolManager.sol`

Has `uint256[50] __gap` via `KasuAccessControllable` — safe for new storage.

#### New Storage Variables

```solidity
/// @dev Allowed additional assets per pool.
mapping(address pool => mapping(address asset => bool)) private _allowedAdditionalAssets;

/// @dev List of additional assets per pool (for iteration).
mapping(address pool => address[]) private _poolAdditionalAssets;
```

#### New Methods (existing signatures UNCHANGED)

```solidity
/// @notice Request deposit in an additional asset.
function requestDepositInAsset(
    address lendingPool,
    address tranche,
    address asset,
    uint256 maxAmount,
    uint256 fixedTermConfigId,
    bytes calldata depositData
) public payable whenNotPaused validLendingPool(lendingPool)
  isUserNotBlocked(msg.sender) isUserAllowed(msg.sender)
  returns (uint256 dNftID)
{
    require(_allowedAdditionalAssets[lendingPool][asset], "asset not allowed");
    IERC20(asset).safeTransferFrom(msg.sender, address(this), maxAmount);
    IERC20(asset).safeIncreaseAllowance(lendingPools[lendingPool].pendingPool, maxAmount);
    _userManager.userRequestedDeposit(msg.sender, lendingPool);
    dNftID = IPendingPool(lendingPools[lendingPool].pendingPool)
        .requestDepositInAsset(msg.sender, tranche, asset, maxAmount, fixedTermConfigId);
    if (depositData.length > 0) {
        emit DepositDataAdded(lendingPool, dNftID, depositData);
    }
}

/// @notice Request deposit in additional asset with KYC.
function requestDepositInAssetWithKyc(
    address lendingPool, address tranche, address asset,
    uint256 maxAmount, uint256 fixedTermConfigId,
    bytes calldata depositData, KycData calldata kycData
) external payable whenNotPaused validLendingPool(lendingPool)
  isUserNotBlocked(msg.sender) isUserKycd(kycData)
  returns (uint256 dNftID)
{
    // Same as above but with KYC check
}

/// @notice Repay owed funds in additional asset.
function repayOwedFundsInAsset(
    address lendingPool, address asset, uint256 amount, address repaymentAddress
) external whenNotPaused validLendingPool(lendingPool)
  onlyLendingPoolRole(lendingPool, ROLE_POOL_FUNDS_MANAGER, msg.sender)
{
    IERC20(asset).safeTransferFrom(repaymentAddress, address(this), amount);
    IERC20(asset).safeIncreaseAllowance(lendingPool, amount);
    ILendingPool(lendingPool).repayOwedFundsInAsset(amount, asset);
}

/// @notice Deposit first loss capital in additional asset.
function depositFirstLossCapitalInAsset(
    address lendingPool, address asset, uint256 amount
) external whenNotPaused validLendingPool(lendingPool)
  onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
{
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(asset).safeIncreaseAllowance(lendingPool, amount);
    ILendingPool(lendingPool).depositFirstLossCapitalInAsset(amount, asset);
}

/// @notice Add an additional asset to a pool.
function addPoolAdditionalAsset(address lendingPool, address asset)
    external onlyLendingPoolRole(lendingPool, ROLE_POOL_ADMIN, msg.sender)
{
    require(!_allowedAdditionalAssets[lendingPool][asset], "already added");
    _allowedAdditionalAssets[lendingPool][asset] = true;
    _poolAdditionalAssets[lendingPool].push(asset);
}

/// @notice Remove an additional asset from a pool (no new deposits, existing continue).
function removePoolAdditionalAsset(address lendingPool, address asset)
    external onlyLendingPoolRole(lendingPool, ROLE_POOL_ADMIN, msg.sender)
{
    _allowedAdditionalAssets[lendingPool][asset] = false;
}

/// @notice Check if asset is allowed for pool.
function isAdditionalAssetAllowed(address lendingPool, address asset) external view returns (bool) {
    return _allowedAdditionalAssets[lendingPool][asset];
}

/// @notice Get all additional assets for a pool.
function poolAdditionalAssets(address lendingPool) external view returns (address[] memory) {
    return _poolAdditionalAssets[lendingPool];
}

/// @notice Force immediate withdrawal in additional asset.
function forceImmediateWithdrawalInAsset(
    address lendingPool, address tranche, address user, uint256 shares, address asset
) external whenNotPaused validLendingPool(lendingPool)
  onlyLendingPoolRole(lendingPool, ROLE_POOL_MANAGER, msg.sender)
  returns (uint256)
{
    return ILendingPool(lendingPool).forceImmediateWithdrawalInAsset(tranche, user, shares, asset);
}
```

---

### 5. ClearingCoordinator (TransparentProxy)

**File**: `src/core/clearing/ClearingCoordinator.sol`

#### Modified Methods

**`doClearing()`** — needs per-asset orchestration. Two approaches:

**Option A — New `doClearingForAsset()` method:**
```solidity
/// @notice Executes clearing for a specific additional asset.
function doClearingForAsset(
    address lendingPool,
    uint256 targetEpoch,
    address asset,
    uint256 fixedTermDepositBatchSize,
    uint256 priorityCalculationBatchSize,
    uint256 acceptRequestsBatchSize,
    ClearingConfiguration calldata clearingConfig,
    bool isConfigOverridden
) external onlyLendingPoolManager {
    // Same flow as doClearing but:
    // Step 1: applyInterestsPerAsset(epoch, asset)
    // Step 2: calculatePendingRequestsPriorityBatchPerAsset(epoch, batchSize, asset)
    // Step 3: calculateAndSaveAcceptedRequestsPerAsset(config, balancePerAsset, epoch, asset)
    // Step 4: executeAcceptedRequestsBatchPerAsset(epoch, batchSize, asset)
    // Step 5: drawFundsInAsset(drawAmount, asset)
    // End: payOwedFeesPerAsset(asset)
}
```

**Option B — Existing `doClearing()` loops over assets internally:**
More gas per call but simpler caller interface. The clearing script would call `doClearing()` once and it handles all assets.

**Recommended: Option A** — explicit per-asset clearing calls. Gives operators control over gas usage and ordering.

#### New Storage

```solidity
/// @dev Per-asset clearing status.
mapping(address lendingPool => mapping(uint256 epoch => mapping(address asset => ClearingStatus)))
    private _lendingPoolClearingStatusPerAsset;

/// @dev Per-asset clearing config.
mapping(address lendingPool => mapping(uint256 epoch => mapping(address asset => AppliedClearingConfiguration)))
    private _clearingConfigPerLendingPoolAndEpochPerAsset;
```

The existing `doClearing()` remains unchanged — it clears the base asset only.

---

### 6. FeeManager (TransparentProxy)

**File**: `src/core/FeeManager.sol`

Has `uint256[50] __gap` via `KasuAccessControllable` — safe for new storage.

#### New Storage

```solidity
/// @dev Per-asset protocol fee amounts.
mapping(address asset => uint256) public totalProtocolFeeAmountPerAsset;
```

#### New Methods

```solidity
/// @notice Receives and distributes fees in an additional asset.
function emitFeesInAsset(uint256 amount, address asset) external whenNotPaused {
    require(_lendingPoolManager.isLendingPool(msg.sender), "invalid pool");
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

    // For additional assets: all fees go to protocol (no ecosystem fee to KSULocking)
    // KSULocking only handles base asset fees.
    // This can be extended later with swap-to-base before KSULocking emission.
    totalProtocolFeeAmountPerAsset[asset] += amount;
    emit FeesEmittedInAsset(msg.sender, asset, amount);
}

/// @notice Claims protocol fees in a specific asset.
function claimProtocolFeesInAsset(address asset)
    external whenNotPaused onlyRole(ROLE_PROTOCOL_FEE_CLAIMER, msg.sender)
{
    address receiver = _systemVariables.protocolFeeReceiver();
    uint256 amount = totalProtocolFeeAmountPerAsset[asset];
    totalProtocolFeeAmountPerAsset[asset] = 0;
    IERC20(asset).safeTransfer(receiver, amount);
    emit ProtocolFeesClaimedInAsset(receiver, asset, amount);
}
```

Existing `emitFees()` and `claimProtocolFees()` remain unchanged for base asset.

---

### 7. FixedTermDeposit (TransparentProxy)

**File**: `src/core/lendingPool/FixedTermDeposit.sol`

#### New Storage (appended — NOTE: no `__gap` in this contract, but appending is safe)

```solidity
/// @dev Per-asset fixed term deposit tracking.
/// Maps lendingPool => fixedTermDepositId => asset address.
mapping(address => mapping(uint256 => address)) private _fixedTermDepositAsset;
```

#### Changes

Fixed term deposits lock tranche shares. Since tranche shares are now per-asset, the lock must track which asset's shares are being locked. The `lockFixedTermDepositAutomatically()` method needs an asset parameter, and the unlock/withdrawal path must use the correct per-asset share redemption.

---

### 8. Interfaces

New interface files or extensions needed:

```solidity
// ILendingPool additions
function acceptDepositInAsset(address tranche, address user, uint256 amount, address asset) external returns (uint256);
function acceptWithdrawalInAsset(address tranche, address user, uint256 shares, address asset) external returns (uint256);
function drawFundsInAsset(uint256 amount, address asset) external;
function repayOwedFundsInAsset(uint256 amount, address asset) external;
function applyInterestsPerAsset(uint256 epoch, address asset) external;
function availableFundsPerAsset(address asset) external view returns (uint256);
function depositFirstLossCapitalInAsset(uint256 amount, address asset) external;
function forceImmediateWithdrawalInAsset(address tranche, address user, uint256 shares, address asset) external returns (uint256);

// IPendingPool additions
function requestDepositInAsset(address user, address tranche, address asset, uint256 amount, uint256 ftdConfigId) external returns (uint256);
function requestWithdrawalInAsset(address user, address tranche, address asset, uint256 shares) external returns (uint256);
function depositNftAsset(uint256 dNftID) external view returns (address);
function withdrawalNftAsset(uint256 wNftID) external view returns (address);
function pendingDepositAmountForCurrentEpochPerAsset(address asset) external view returns (uint256);

// ILendingPoolTranche additions
function depositInAsset(uint256 assets, address receiver, address asset) external returns (uint256);
function redeemInAsset(uint256 shares, address receiver, address owner, address asset) external returns (uint256);
function removeUserActiveSharesPerAsset(address user, uint256 shares, address asset) external;
function applyInterestPerAsset(uint256 interestAmount, address asset) external;
function userActiveAssetsPerAsset(address user, address asset) external view returns (uint256);
function convertToAssetsPerAsset(uint256 shares, address asset) external view returns (uint256);

// IFeeManager additions
function emitFeesInAsset(uint256 amount, address asset) external;
function claimProtocolFeesInAsset(address asset) external;

// ILendingPoolManager additions
function requestDepositInAsset(address lendingPool, address tranche, address asset, uint256 maxAmount, uint256 ftdConfigId, bytes calldata depositData) external returns (uint256);
function repayOwedFundsInAsset(address lendingPool, address asset, uint256 amount, address repaymentAddress) external;
function addPoolAdditionalAsset(address lendingPool, address asset) external;
function removePoolAdditionalAsset(address lendingPool, address asset) external;
function isAdditionalAssetAllowed(address lendingPool, address asset) external view returns (bool);
function poolAdditionalAssets(address lendingPool) external view returns (address[] memory);
```

---

### 9. Events

New events to add across contracts:

```solidity
// LendingPool
event DepositAcceptedInAsset(address indexed user, address indexed tranche, address indexed asset, uint256 amount, uint256 shares);
event WithdrawalAcceptedInAsset(address indexed user, address indexed tranche, address indexed asset, uint256 shares, uint256 amount);
event FundsDrawnInAsset(address indexed asset, uint256 amount);
event OwedFundsRepaidInAsset(address indexed asset, uint256 userRepaid, uint256 feesPaid);
event InterestAppliedPerAsset(address indexed tranche, address indexed asset, uint256 epoch, uint256 amount);
event FirstLossCapitalAddedInAsset(address indexed asset, uint256 amount);

// PendingPool
event DepositRequestCreatedInAsset(address indexed user, address indexed tranche, address indexed asset, uint256 dNftID, uint256 amount);
event DepositRequestAcceptedInAsset(address indexed user, address indexed tranche, address indexed asset, uint256 dNftID, uint256 amount, uint256 shares);

// FeeManager
event FeesEmittedInAsset(address indexed lendingPool, address indexed asset, uint256 amount);
event ProtocolFeesClaimedInAsset(address indexed receiver, address indexed asset, uint256 amount);

// LendingPoolManager
event PoolAdditionalAssetAdded(address indexed lendingPool, address indexed asset);
event PoolAdditionalAssetRemoved(address indexed lendingPool, address indexed asset);
```
