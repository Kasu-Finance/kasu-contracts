// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import "../_utils/LendingPoolTestUtils.sol";

contract LendingPoolFactorTest is LendingPoolTestUtils {
    function setUp() public {
        __lendingPool_setUp();
    }

    function test_incorrectMinimumTrancheCount() public {
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreatorAccount);

        uint256 minDepositAmount = 500 * 1e6;
        uint256 maxDepositAmount = 100_000 * 1e6;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        uint256 totalDesiredLoanAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](0);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidity,
            createTrancheConfig,
            lendingPoolAdminAccount,
            lendingPoolLoanManagerAccount,
            totalDesiredLoanAmount
        );

        vm.startPrank(lendingPoolCreatorAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.PoolConfigurationIsIncorrect.selector, "tranche count less than minimum"
            )
        );
        lendingPoolManager.createPool(createPoolConfig);
        vm.stopPrank();
    }

    function test_incorrectMaximumTrancheCount() public {
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreatorAccount);

        uint256 minDepositAmount = 500 * 1e6;
        uint256 maxDepositAmount = 100_000 * 1e6;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        uint256 totalDesiredLoanAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](4);
        createTrancheConfig[0] = CreateTrancheConfig("Junior", "JR", 10_00, 5_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig("Mezzo", "MZ", 20_00, 4_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[2] = CreateTrancheConfig("Senior", "SR", 30_00, 3_00, minDepositAmount, maxDepositAmount);
        createTrancheConfig[3] = CreateTrancheConfig("Extra", "XT", 40_00, 3_00, minDepositAmount, maxDepositAmount);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidity,
            createTrancheConfig,
            lendingPoolAdminAccount,
            lendingPoolLoanManagerAccount,
            totalDesiredLoanAmount
        );

        vm.startPrank(lendingPoolCreatorAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingPool.PoolConfigurationIsIncorrect.selector, "tranche count more than maximum"
            )
        );
        lendingPoolManager.createPool(createPoolConfig);
        vm.stopPrank();
    }
}
