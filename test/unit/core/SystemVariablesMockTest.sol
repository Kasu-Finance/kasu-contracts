// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../_utils/BaseTestUtils.sol";
import "../../../src/core/SystemVariables.sol";
import "../../../src/shared/CommonErrors.sol";
import "../../shared/MockKsuPrice.sol";

contract SystemVariablesMockTest is BaseTestUtils {
    SystemVariables internal systemVariables;
    MockKsuPrice internal ksuPrice;
    IKasuController internal kasuController;

    function setUp() public {
        ksuPrice = new MockKsuPrice();
        kasuController = IKasuController(address(0xcccc));

        SystemVariables systemVariablesImpl = new SystemVariables(ksuPrice, kasuController);
        TransparentUpgradeableProxy systemVariablesProxy =
            new TransparentUpgradeableProxy(address(systemVariablesImpl), address(proxyAdmin), "");
        systemVariables = SystemVariables(address(systemVariablesProxy));

        vm.mockCall(address(kasuController), abi.encodeWithSelector(IAccessControl.hasRole.selector), abi.encode(false));

        vm.mockCall(
            address(kasuController),
            abi.encodeWithSelector(IAccessControl.hasRole.selector, ROLE_KASU_ADMIN, admin),
            abi.encode(true)
        );
    }

    function test_getCurrentEpochNumber() public {
        _initalize();
        assertEq(systemVariables.getCurrentEpochNumber(), 0);

        skip(uint256(6 days + 1));
        assertEq(systemVariables.getCurrentEpochNumber(), 0);

        skip(uint256(1 days));
        assertEq(systemVariables.getCurrentEpochNumber(), 1);
    }

    function test_getEpochStartTimestamp() public {
        _initalize();
        assertEq(systemVariables.getEpochStartTimestamp(0), block.timestamp);

        assertEq(systemVariables.getEpochStartTimestamp(1), block.timestamp + 1 weeks);
    }

    function test_getNextEpochStartTimestamp() public {
        _initalize();

        uint256 nextEpochStartTime = block.timestamp + 1 weeks;
        assertEq(systemVariables.getNextEpochStartTimestamp(), nextEpochStartTime);

        skip(1 days);
        assertEq(systemVariables.getNextEpochStartTimestamp(), nextEpochStartTime);

        skip(1 weeks);
        assertEq(systemVariables.getNextEpochStartTimestamp(), nextEpochStartTime + 1 weeks);
    }

    function test_getEpochDuration() public {
        _initalize();
        assertEq(systemVariables.getEpochDuration(), 1 weeks);
    }

    function test_getCurrentRequestEpoch() public {
        _initalize();
        assertEq(systemVariables.getCurrentRequestEpoch(), 0);

        skip(1 days);
        assertEq(systemVariables.getCurrentRequestEpoch(), 0);

        skip(5 days);
        assertEq(systemVariables.getCurrentRequestEpoch(), 1);

        skip(12 hours);
        assertEq(systemVariables.getCurrentRequestEpoch(), 1);

        skip(12 hours);
        assertEq(systemVariables.getCurrentRequestEpoch(), 1);

        skip(6 days);
        assertEq(systemVariables.getCurrentRequestEpoch(), 2);
    }

    function test_isClearingTime() public {
        _initalize();
        assertEq(systemVariables.isClearingTime(), false);

        skip(6 days);
        assertEq(systemVariables.isClearingTime(), true);

        skip(12 hours);
        assertEq(systemVariables.isClearingTime(), true);

        skip(12 hours);
        assertEq(systemVariables.isClearingTime(), false);
    }

    function test_ksuEpochTokenPrice() public {
        _initalize();

        assertEq(systemVariables.ksuEpochTokenPrice(), ksuPrice.getKsuTokenPrice());

        uint256 newKsuTokenPrice = 3e18;
        ksuPrice.setKsuTokenPrice(newKsuTokenPrice);

        skip(1 weeks);

        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), newKsuTokenPrice);
    }

    function test_priceUpdateEpoch() public {
        _initalize();
        assertEq(systemVariables.priceUpdateEpoch(), 0);

        skip(8 days);
        assertEq(systemVariables.priceUpdateEpoch(), 0);

        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.priceUpdateEpoch(), 1);
    }

    function test_updateKsuEpochTokenPrice() public {
        _initalize();

        uint256 initialKsuPrice = ksuPrice.getKsuTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), initialKsuPrice);

        uint256 newKsuTokenPrice = 3e18;
        ksuPrice.setKsuTokenPrice(newKsuTokenPrice);
        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), initialKsuPrice);

        skip(6 days);
        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), initialKsuPrice);

        // new epoch
        skip(1 days);
        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), newKsuTokenPrice);

        // new epoch
        skip(1 weeks);
        newKsuTokenPrice = 4e18;
        ksuPrice.setKsuTokenPrice(newKsuTokenPrice);
        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), newKsuTokenPrice);
    }

    function test_clearingPeriodLength() public {
        SystemVariablesSetup memory systemVariablesSetup = _initalize();
        assertEq(systemVariables.clearingPeriodLength(), systemVariablesSetup.clearingPeriodLength);
    }

    function test_performanceFee() public {
        SystemVariablesSetup memory systemVariablesSetup = _initalize();
        assertEq(systemVariables.performanceFee(), systemVariablesSetup.performanceFee);
    }

    function test_setPerformanceFee() public {
        _initalize();

        uint256 newPerformanceFee = 20_00;
        hoax(admin);
        systemVariables.setPerformanceFee(newPerformanceFee);

        assertEq(systemVariables.performanceFee(), newPerformanceFee);

        // test revert invalid configuration
        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.setPerformanceFee(100_01);

        // test revert no role
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        systemVariables.setPerformanceFee(newPerformanceFee);
    }

    function test_loyaltyThresholds() public {
        SystemVariablesSetup memory systemVariablesSetup = _initalize();

        uint256[] memory loyaltyThresholds = systemVariables.loyaltyThresholds();
        assertEq(loyaltyThresholds[0], systemVariablesSetup.loyaltyThresholds[0]);
        assertEq(loyaltyThresholds[1], systemVariablesSetup.loyaltyThresholds[1]);
    }

    function test_setLoyaltyThreshold() public {
        _initalize();

        uint256[] memory newLoyaltyThresholds = new uint256[](3);
        newLoyaltyThresholds[0] = 2_00;
        newLoyaltyThresholds[1] = 4_00;
        newLoyaltyThresholds[2] = 6_00;

        hoax(admin);
        systemVariables.setLoyaltyThresholds(newLoyaltyThresholds);

        uint256[] memory loyaltyThresholds = systemVariables.loyaltyThresholds();
        assertEq(loyaltyThresholds.length, newLoyaltyThresholds.length);
        assertEq(loyaltyThresholds[0], newLoyaltyThresholds[0]);
        assertEq(loyaltyThresholds[1], newLoyaltyThresholds[1]);
        assertEq(loyaltyThresholds[2], newLoyaltyThresholds[2]);

        // test revert lower threshold than previous
        newLoyaltyThresholds[2] = 3_00;

        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.setLoyaltyThresholds(newLoyaltyThresholds);

        // test revert too many thresholds
        newLoyaltyThresholds = new uint256[](11);
        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.setLoyaltyThresholds(newLoyaltyThresholds);

        // test revert no role
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        systemVariables.setLoyaltyThresholds(newLoyaltyThresholds);

        // test revert - configure during clearing period
        skip(6 days);
        newLoyaltyThresholds = new uint256[](0);
        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(ISystemVariables.CannotConfigureDuringClearingPeriod.selector));
        systemVariables.setLoyaltyThresholds(newLoyaltyThresholds);
    }

    function test_setDefaultTrancheInterestChangeEpochDelay() public {
        _initalize();

        hoax(admin);
        systemVariables.setDefaultTrancheInterestChangeEpochDelay(2);

        assertEq(systemVariables.defaultTrancheInterestChangeEpochDelay(), 2);
    }

    function _initalize() internal returns (SystemVariablesSetup memory systemVariablesSetup) {
        systemVariablesSetup.firstEpochStartTimestamp = block.timestamp;
        systemVariablesSetup.clearingPeriodLength = 1 days;
        systemVariablesSetup.performanceFee = 10_00;
        systemVariablesSetup.loyaltyThresholds = new uint256[](2);
        systemVariablesSetup.loyaltyThresholds[0] = 1_00;
        systemVariablesSetup.loyaltyThresholds[1] = 3_00;
        systemVariablesSetup.defaultTrancheInterestChangeEpochDelay = 4;
        systemVariablesSetup.ecosystemFeeRate = 50_00;
        systemVariablesSetup.protocolFeeRate = 50_00;
        systemVariablesSetup.protocolFeeReceiver = address(0xfee);

        systemVariables.initialize(systemVariablesSetup);
    }
}
