// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../../src/shared/interfaces/IKasuController.sol";
import "../../../src/core/UserLoyaltyRewards.sol";
import "../../shared/MockKsuPrice.sol";
import "../../shared/MockERC20Permit.sol";
import {BaseTestUtils} from "../_utils/BaseTestUtils.sol";
import "forge-std/Test.sol";

contract UserLoyaltyRewardsMockTest is BaseTestUtils {
    MockKsuPrice internal _mockKsuPrice;
    MockERC20Permit internal _ksu;
    IKasuController internal _kasuController;
    address internal _userManager;

    UserLoyaltyRewards internal _userLoyaltyRewards;

    function setUp() public {
        _mockKsuPrice = new MockKsuPrice();
        _ksu = new MockERC20Permit("Kasu", "KSU", 18);
        _kasuController = IKasuController(address(0xcccc));
        _userManager = address(0xdddd);

        UserLoyaltyRewards userLoyaltyRewardsImpl = new UserLoyaltyRewards(_mockKsuPrice, _ksu, _kasuController);
        TransparentUpgradeableProxy userLoyaltyRewardsProxy =
            new TransparentUpgradeableProxy(address(userLoyaltyRewardsImpl), address(proxyAdmin), "");
        _userLoyaltyRewards = UserLoyaltyRewards(address(userLoyaltyRewardsProxy));

        _userLoyaltyRewards.initialize(_userManager, true);

        vm.mockCall(
            address(_kasuController), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false)
        );

        vm.mockCall(
            address(_kasuController), abi.encodeCall(IAccessControl.hasRole, (ROLE_KASU_ADMIN, admin)), abi.encode(true)
        );
    }

    function test_setRewardRatesPerLoyaltyLevel() public {
        // ARRANGE
        LoyaltyEpochRewardRateInput[] memory loyaltyEpochRewardRatesInput = new LoyaltyEpochRewardRateInput[](2);
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, 100);
        loyaltyEpochRewardRatesInput[1] = LoyaltyEpochRewardRateInput(2, 200);

        // ACT
        vm.prank(admin);
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);

        // ASSERT
        uint256 epochRewardRate0 = _userLoyaltyRewards.loyaltyEpochRewardRates(0);
        uint256 epochRewardRate1 = _userLoyaltyRewards.loyaltyEpochRewardRates(1);
        uint256 epochRewardRate2 = _userLoyaltyRewards.loyaltyEpochRewardRates(2);

        assertEq(epochRewardRate0, 0);
        assertEq(epochRewardRate1, 100);
        assertEq(epochRewardRate2, 200);

        // ACT & ASSERT
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, INTEREST_RATE_FULL_PERCENT / 20 + 1);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);
    }

    function test_setDoEmitRewards() public {
        // ARRANGE
        vm.startPrank(admin);
        _userLoyaltyRewards.setDoEmitRewards(true);
        bool doEmitRewards = _userLoyaltyRewards.doEmitRewards();
        assertEq(doEmitRewards, true);

        // ACT
        _userLoyaltyRewards.setDoEmitRewards(false);

        // ASSERT
        doEmitRewards = _userLoyaltyRewards.doEmitRewards();
        assertEq(doEmitRewards, false);

        // ACT

        _userLoyaltyRewards.setDoEmitRewards(true);

        // ASSERT
        doEmitRewards = _userLoyaltyRewards.doEmitRewards();
        assertEq(doEmitRewards, true);

        // ACT & ASSERT
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _userLoyaltyRewards.setDoEmitRewards(true);
    }

    function test_emitUserLoyaltyReward() public {
        // ARRANGE
        LoyaltyEpochRewardRateInput[] memory loyaltyEpochRewardRatesInput = new LoyaltyEpochRewardRateInput[](2);
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, 1e15); // 0.1% per epoch
        loyaltyEpochRewardRatesInput[1] = LoyaltyEpochRewardRateInput(2, 2e15); // 0.2% per epoch

        vm.prank(admin);
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);

        uint256 aliceDeposited = 1000 * 1e6;
        uint256 aliceLoyalty = 0;

        uint256 bobDeposited = 1000 * 1e6;
        uint256 bobLoyalty = 1;

        uint256 carolDeposited = 10000 * 1e6;
        uint256 carolLoyalty = 2;

        // KSU token price is 2.0 USDC
        uint256 tokenPrice = 2e18;
        _mockKsuPrice.setKsuTokenPrice(tokenPrice);

        // ACT
        vm.startPrank(_userManager);
        _userLoyaltyRewards.emitUserLoyaltyReward(alice, 0, aliceLoyalty, aliceDeposited);
        _userLoyaltyRewards.emitUserLoyaltyReward(bob, 0, bobLoyalty, bobDeposited);
        _userLoyaltyRewards.emitUserLoyaltyReward(carol, 0, carolLoyalty, carolDeposited);

        // ASSERT

        // 1000 * 0.1% / 2.0 = 0.5
        uint256 bobReward = 0.5 * 1e18;

        // 10000 * 0.2% / 2.0 = 10
        uint256 carolReward = 10 * 1e18;

        assertEq(_userLoyaltyRewards.userRewards(alice), 0);
        assertEq(_userLoyaltyRewards.userRewards(bob), bobReward);
        assertEq(_userLoyaltyRewards.userRewards(carol), carolReward);
        assertEq(_userLoyaltyRewards.totalUnclaimedRewards(), bobReward + carolReward);

        // ACT & ASSERT
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IUserLoyaltyRewards.OnlyUserManager.selector));
        _userLoyaltyRewards.emitUserLoyaltyReward(alice, 0, aliceLoyalty, aliceDeposited);
    }

    function test_emitUserLoyaltyRewardBatch() public {
        // ARRANGE
        LoyaltyEpochRewardRateInput[] memory loyaltyEpochRewardRatesInput = new LoyaltyEpochRewardRateInput[](2);
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, 1e15); // 0.1% per epoch
        loyaltyEpochRewardRatesInput[1] = LoyaltyEpochRewardRateInput(2, 2e15); // 0.2% per epoch

        vm.prank(admin);
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);

        uint256 aliceDeposited = 1000 * 1e6;
        uint256 aliceLoyalty = 0;

        uint256 bobDeposited = 1000 * 1e6;
        uint256 bobLoyalty = 1;

        uint256 carolDeposited = 10000 * 1e6;
        uint256 carolLoyalty = 2;

        // contract KSU token price is 1.0 USDC
        uint256 tokenPrice = 1e18;
        _mockKsuPrice.setKsuTokenPrice(tokenPrice);

        // ACT

        // manual KSU token price is 2.0 USDC
        uint256 manualTokenPrice = 2e18;
        UserRewardInput[] memory userRewardInputs = new UserRewardInput[](3);
        userRewardInputs[0] = UserRewardInput(alice, 0, aliceLoyalty, aliceDeposited);
        userRewardInputs[1] = UserRewardInput(bob, 0, bobLoyalty, bobDeposited);
        userRewardInputs[2] = UserRewardInput(carol, 0, carolLoyalty, carolDeposited);
        vm.prank(admin);
        _userLoyaltyRewards.emitUserLoyaltyRewardBatch(userRewardInputs, manualTokenPrice);

        // ASSERT

        // 1000 * 0.1% / 2.0 = 0.5
        uint256 bobReward = 0.5 * 1e18;

        // 10000 * 0.2% / 2.0 = 10
        uint256 carolReward = 10 * 1e18;

        assertEq(_userLoyaltyRewards.userRewards(alice), 0);
        assertEq(_userLoyaltyRewards.userRewards(bob), bobReward);
        assertEq(_userLoyaltyRewards.userRewards(carol), carolReward);
        assertEq(_userLoyaltyRewards.totalUnclaimedRewards(), bobReward + carolReward);

        // ACT & ASSERT
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _userLoyaltyRewards.emitUserLoyaltyRewardBatch(userRewardInputs, tokenPrice);
    }

    function test_claimReward() public {
        // ARRANGE
        LoyaltyEpochRewardRateInput[] memory loyaltyEpochRewardRatesInput = new LoyaltyEpochRewardRateInput[](2);
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, 1e15); // 0.1% per epoch
        loyaltyEpochRewardRatesInput[1] = LoyaltyEpochRewardRateInput(2, 2e15); // 0.2% per epoch

        vm.prank(admin);
        _userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);

        // KSU token price is 2.0 USDC
        _mockKsuPrice.setKsuTokenPrice(2e18);

        vm.startPrank(_userManager);
        _userLoyaltyRewards.emitUserLoyaltyReward(alice, 0, 0, 1000 * 1e6);
        _userLoyaltyRewards.emitUserLoyaltyReward(bob, 0, 1, 1000 * 1e6);
        _userLoyaltyRewards.emitUserLoyaltyReward(carol, 0, 2, 10000 * 1e6);
        vm.stopPrank();

        // 1000 * 0.1% / 2.0 = 0.5
        uint256 bobReward = 0.5 * 1e18;

        // 10000 * 0.2% / 2.0 = 10
        uint256 carolReward = 10 * 1e18;

        // ACT
        vm.prank(bob);
        _userLoyaltyRewards.claimReward(type(uint256).max);

        // ASSERT
        assertEq(_ksu.balanceOf(bob), 0);

        // ARRANGE
        _ksu.mint(address(_userLoyaltyRewards), 1000 * 1e18);

        // ACT
        vm.prank(alice);
        _userLoyaltyRewards.claimReward(type(uint256).max);
        vm.prank(bob);
        _userLoyaltyRewards.claimReward(type(uint256).max);
        vm.prank(carol);
        uint256 carolPartialReward = 4 * 1e18;
        _userLoyaltyRewards.claimReward(carolPartialReward);

        // ASSERT
        assertEq(_ksu.balanceOf(alice), 0);
        assertEq(_ksu.balanceOf(bob), bobReward);
        assertEq(_ksu.balanceOf(carol), carolPartialReward);

        // ACT
        vm.prank(carol);
        _userLoyaltyRewards.claimReward(type(uint256).max);

        // ASSERT
        assertEq(_ksu.balanceOf(carol), carolReward);
    }

    function test_recoverERC20() public {
        // ARRANGE
        _ksu.mint(address(_userLoyaltyRewards), 1000 * 1e18);

        // ACT
        vm.prank(admin);
        uint256 recoverAmount = 300 * 1e18;
        address recipient = address(0x9876);
        _userLoyaltyRewards.recoverERC20(address(_ksu), recoverAmount, recipient);

        // ASSERT
        assertEq(_ksu.balanceOf(recipient), recoverAmount);
        assertEq(_ksu.balanceOf(address(_userLoyaltyRewards)), 1000 * 1e18 - recoverAmount);

        // ACT & ASSERT
        vm.startPrank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        _userLoyaltyRewards.recoverERC20(address(_ksu), recoverAmount, alice);
    }
}
