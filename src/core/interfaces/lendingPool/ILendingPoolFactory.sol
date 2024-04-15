// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ILendingPoolManager.sol";
import "./ILendingPool.sol";

/**
 * @notice Configuration for creating a new lending pool.
 * @custom:member poolName Pool name. ERC20 token name.
 * @custom:member poolSymbol Pool symbol. ERC20 token symbol.
 * @custom:member targetExcessLiquidityPercentage Target excess liquidity percentage.
 * @custom:member minExcessLiquidityPercentage Minimum excess liquidity percentage.
 * @custom:member tranches Tranche configurations.
 * @custom:member poolAdmin Address of the pool admin.
 * @custom:member drawRecipient Address to receive the funds drawn from the pool.
 * @custom:member desiredDrawAmount Desired draw amount at the first lending pool clearing processing.
 */
struct CreatePoolConfig {
    string poolName;
    string poolSymbol;
    uint256 targetExcessLiquidityPercentage;
    uint256 minExcessLiquidityPercentage;
    CreateTrancheConfig[] tranches;
    address poolAdmin;
    address drawRecipient;
    uint256 desiredDrawAmount;
}

/**
 * @notice Tranche configuration for creating a new lending pool.
 * @custom:member ratio Tranche ratio. 100% is 1e5. All tranche ratios should sum up to 100%.
 * @custom:member interestRate Tranche interest rate. 100% is 1e18.
 * @custom:member minDepositAmount Minimum tranche deposit request amount.
 * @custom:member maxDepositAmount Maximum tranche deposit request amount.
 */
struct CreateTrancheConfig {
    uint256 ratio;
    uint256 interestRate;
    uint256 minDepositAmount;
    uint256 maxDepositAmount;
}

/**
 * @notice Lending pool deployment information.
 * @custom:member lendingPool Lending pool address.
 * @custom:member pendingPool Pending pool address.
 * @custom:member tranches Lending pool tranche addresses.
 */
struct LendingPoolDeployment {
    address lendingPool;
    address pendingPool;
    address[] tranches;
}

interface ILendingPoolFactory {
    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    function createPool(CreatePoolConfig calldata createPoolConfig)
        external
        returns (LendingPoolDeployment memory lendingPoolDeployment);

    event PoolCreated(
        address indexed lendingPool, LendingPoolDeployment lendingPoolDeployment, PoolConfiguration poolConfiguration
    );
}
