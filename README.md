# Kasu

Kasu is an innovative RWA (Real World Asset) private credit lending platform that leverages proprietary technology to optimize businesses' cash flows and enhance credit risk management. Kasu brings together DeFi investors and lending entities, facilitating the origination of loans to business borrowers seeking growth capital. The platform's real-time risk management and reporting democratizes access to real-world interest opportunities that were previously unavailable to DeFi investors.

At the core of Kasu's ecosystem are lending pools, which allow KYC-verified Liquidity Providers to deposit USDC and earn interest. These pools can be divided into tranches, with each tranche offering a unique risk-return profile to cater to diverse investor preferences. The platform incorporates a loyalty level system, prioritizing Liquidity Providers based on their KSU token locking commitment and aligning ecosystem incentives.

Kasu's Accounts Receivable Automation Software and Smart Payments optimize borrowers' cash flows and reduce default risk before lending against their receivables. Kasu distinguishes itself from other RWA lending platforms, which primarily lend money as a commoditized product, by providing deep value-add across the entire lending value chain. With its permissioned pools, epoch-based structure, and KYC requirements, Kasu maintains a high level of security and compliance while leveraging blockchain's transactional and settlement efficiencies.

## Testing

### Install Foundry

To run tests you need to have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

`forge install`

### Test

To run tests execute:

`forge test`

### Coverage

```text
forge coverage --report lcov
genhtml lcov.info --branch-coverage -o coverage
```

The html report is then available at `./coverage/src/index.html`.

The `genhtml` tool is not available for Windows, but WSL can be used to bypass this limitation.

## Docs

Run `forge doc --build`

## Deploying

### Install

To deploy you need to have JavaScript installed.

Run `npm install` in the root of the repository.

### Deploy

Run `npx hardhat --network localhost deploy` to deploy to a local hardhat node.

## Smart Contract Overview

Implementation can be found inside `./src` folder.
Tests can be found inside `./test` folder.

Core folder contains four other sub-folders:

- `core`
- `locking`
- `shared`
- `token`

### Core

Core contracts contain main core logic regarding lending pools and lending related operations.

#### Lending Pool

Lending pool contracts can be found inside `./src/core/lendingPool` folder.

##### `LendingPoolManager.sol`

This contract is the entry point for all interactions with lending pools in the Kasu system.

##### `LendingPoolFactory.sol`

This contract is responsible for creating new lending pools within the Kasu system.
It deploys and initializes proxy for `LendingPool.sol`, proxy for `PendingPool.sol`, and proxies for `LendingPoolTranche.sol` (one for each tranche).

##### `LendingPool.sol`

This contract is the ledger of the lending pool balances. The lending pool is also an ERC20 token that always represents the total balance of the lending pool relative to the base asset, with the balance of each tranche representing the asset value of that tranche. New deposits mint new tokens to the tranches, while withdrawals burn tokens from the tranches and transfer a proportional amount of the base asset back to the user.

##### `PendingPool.sol`

The contract is responsible for managing pending deposit and withdrawal requests, issuing ERC721 deposit (dNFT) and withdrawal (wNFT) NFTs to users in exchange for deposited assets or tranche shares, respectively. Clearing logic is handled by the ClearingSteps contract, which loops over user pending requests using ERC721Enumerable to process accepted deposits and withdrawals, burning the corresponding NFTs and transferring assets or tranche shares between users and the lending pool.

##### `LendingPoolTranche.sol`

This contract handles lending pool tranche activity, including sending users ERC20 receipt tranche tokens when deposits are cleared and sending assets to the lending pool when withdrawals are cleared. It utilizes ERC4626, `LendingPool.sol` being the only one who can interact with the vault standard functions. In the event of lending pool impairment, users received ERC1155 impairment receipt tokens.

#### Clearing

Clearing contracts can be found inside `./src/core/clearing` folder.

##### `ClearingCoordinator.sol`

This contract is responsible for coordinating the Clearing process for all lending pools in the Kasu system.

##### `ClearingSteps.sol`

This is the abstract contract extended by `PendingPool.sol` for lending pool clearing storage and execution. It is responsible for storing the results from the calculations run during Clearing.

This contract extends `PendingRequestsPriorityCalculation.sol` and `AcceptedRequestsExecution.sol`.

##### `PendingRequestsPriorityCalculation.sol`

Abstract contract extended by `ClearingSteps.sol` containing logic to calculate each user request priority. Used in step 2 of clearing.

##### `AcceptedRequestsExecution.sol`

Abstract contract extended by `ClearingSteps.sol` containing logic to execute each user accepted deposit or withdrawal request. Used in step 4 of clearing.

##### `AcceptedRequestsCalculation.sol`

Contract used by `ClearingSteps.sol` in step 3 of clearing, containing clearing algorithm to calculate current clearing accepted deposit and withdrawal amounts.

#### `SystemVariables.sol`

This contract stores and manages global Kasu system variables, including epoch, KSU epoch price, platform fee, and other global variables. Can only be configurable by Kasu Admin.

#### `KasuAllowlist.sol`

This contract is used to verify if a user is permitted to deposit into Kasu lending pools.

#### `UserManager.sol`

This contract is primarily used to calculate a user loyalty level for the current epoch

#### `FeeManager.sol`

This contract manages and distributes platform protocol fees. Ecosystem fees are sent to the KSU Locking contract and distributed to rKSU holders, while protocol fees are stored in the contract until claimed.

#### `UserLoyaltyRewards.sol`

This contract is used to handle KSU rewards for users based on their active liquidity and loyalty level.

#### `KsuPrice.sol`

This contract is responsible for fetching the current price of the KSU token from the Chainsight oracle.

### Locking

Locking folder contains contracts related to locking KSU tokens.

#### `KSULocking.sol`

This contract is responsible for applying the proportional fees to which KSU token lockers are entitled based on the amount and duration of their lock. It extends `rKSU.sol` contract and it mints non-transferable ERC20 rKSU tokens to KSU Lockers.

#### `KSULockBonus.sol`

This contract is responsible for holding and distributing bonus KSU tokens until depleted.

### Shared

Shared folder contains shared contracts, most important being `KasuController.sol`

#### `KasuController.sol`

This contract is responsible for administration within Kasu, including granting and revoking lending pool roles and pausing and unpausing the system.

#### `KasuAccessControllable.sol`

Abstract contract inherited by all contract that require role based access restrictions.

### Token

Token folder contains ERC20 Kasu (KSU) token implementation.

#### `KSU.sol`

ERC20 Kasu (KSU) token implementation. Implements permit and burn functions.

## Licensing

The primary license for Kasu contracts is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE).

### Exceptions

- All files in src/ are licensed under the license they were originally published with (as indicated in their SPDX headers)
- All files in test/ are licensed under MIT.
