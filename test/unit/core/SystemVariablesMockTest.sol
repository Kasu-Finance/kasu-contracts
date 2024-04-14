// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

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

    function test_initialize_reverts() public {
        skip(2 weeks);

        SystemVariablesSetup memory systemVariablesSetup = _getDefaultInitializeConfig();

        systemVariablesSetup.initialEpochStartTimestamp = block.timestamp + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        _initialize(systemVariablesSetup);

        systemVariablesSetup.initialEpochStartTimestamp = block.timestamp - 1 weeks;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        _initialize(systemVariablesSetup);

        systemVariablesSetup.initialEpochStartTimestamp = block.timestamp;
        systemVariablesSetup.clearingPeriodLength = 0;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        _initialize(systemVariablesSetup);

        systemVariablesSetup.clearingPeriodLength = 1 weeks;
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        _initialize(systemVariablesSetup);
    }

    function test_currentEpochNumber() public {
        skip(2 days);

        SystemVariablesSetup memory systemVariablesSetup = _getDefaultInitializeConfig();
        systemVariablesSetup.initialEpochStartTimestamp = block.timestamp - 1 days;
        _initialize(systemVariablesSetup);

        assertEq(systemVariables.currentEpochNumber(), 0);

        skip(uint256(5 days));
        assertEq(systemVariables.currentEpochNumber(), 0);

        skip(uint256(1 days));
        assertEq(systemVariables.currentEpochNumber(), 1);
    }

    function test_epochStartTimestamp() public {
        _initialize();
        assertEq(systemVariables.epochStartTimestamp(0), block.timestamp);

        assertEq(systemVariables.epochStartTimestamp(1), block.timestamp + 1 weeks);
    }

    function test_nextEpochStartTimestamp() public {
        _initialize();

        uint256 nextEpochStartTime = block.timestamp + 1 weeks;
        assertEq(systemVariables.nextEpochStartTimestamp(), nextEpochStartTime);

        skip(1 days);
        assertEq(systemVariables.nextEpochStartTimestamp(), nextEpochStartTime);

        skip(1 weeks);
        assertEq(systemVariables.nextEpochStartTimestamp(), nextEpochStartTime + 1 weeks);
    }

    function test_epochDuration() public {
        _initialize();
        assertEq(systemVariables.epochDuration(), 1 weeks);
    }

    function test_currentRequestEpoch() public {
        _initialize();

        assertEq(systemVariables.currentRequestEpoch(), 0);

        skip(1 days);
        assertEq(systemVariables.currentRequestEpoch(), 0);

        skip(5 days);
        assertEq(systemVariables.currentRequestEpoch(), 1);

        skip(12 hours);
        assertEq(systemVariables.currentRequestEpoch(), 1);

        skip(12 hours);
        assertEq(systemVariables.currentRequestEpoch(), 1);

        skip(6 days);
        assertEq(systemVariables.currentRequestEpoch(), 2);
    }

    function test_isClearingTime() public {
        _initialize();
        assertEq(systemVariables.isClearingTime(), false);

        skip(6 days);
        assertEq(systemVariables.isClearingTime(), true);

        skip(12 hours);
        assertEq(systemVariables.isClearingTime(), true);

        skip(12 hours);
        assertEq(systemVariables.isClearingTime(), false);
    }

    function test_ksuEpochTokenPrice() public {
        _initialize();

        assertEq(systemVariables.ksuEpochTokenPrice(), ksuPrice.getKsuTokenPrice());

        uint256 newKsuTokenPrice = 3e18;
        ksuPrice.setKsuTokenPrice(newKsuTokenPrice);

        skip(1 weeks);

        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.ksuEpochTokenPrice(), newKsuTokenPrice);
    }

    function test_priceUpdateEpoch() public {
        _initialize();
        assertEq(systemVariables.priceUpdateEpoch(), 0);

        skip(8 days);
        assertEq(systemVariables.priceUpdateEpoch(), 0);

        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.priceUpdateEpoch(), 1);
    }

    function test_updateKsuEpochTokenPrice() public {
        _initialize();

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

    function test_setMaxTrancheInterestRate() public {
        _initialize();

        assertEq(systemVariables.maxTrancheInterestRate(), INTEREST_RATE_FULL_PERCENT / 20);

        uint256 newMaxTrancheInterestRate = 1e17;
        hoax(admin);
        systemVariables.setMaxTrancheInterestRate(newMaxTrancheInterestRate);

        assertEq(systemVariables.maxTrancheInterestRate(), newMaxTrancheInterestRate);

        // test revert no role
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        systemVariables.setMaxTrancheInterestRate(newMaxTrancheInterestRate);
    }

    function test_trancheNameInfo() public {
        _initialize();

        // one tranche
        TrancheInfo memory trancheInfo = systemVariables.trancheNameInfo(1, 0);
        assertEq(trancheInfo.trancheName, "Senior Tranche");

        // two tranches
        trancheInfo = systemVariables.trancheNameInfo(2, 0);
        assertEq(trancheInfo.trancheName, "Junior Tranche");
        trancheInfo = systemVariables.trancheNameInfo(2, 1);
        assertEq(trancheInfo.trancheName, "Senior Tranche");

        // three tranches
        trancheInfo = systemVariables.trancheNameInfo(3, 0);
        assertEq(trancheInfo.trancheName, "Junior Tranche");
        trancheInfo = systemVariables.trancheNameInfo(3, 1);
        assertEq(trancheInfo.trancheName, "Mezzanine Tranche");
        trancheInfo = systemVariables.trancheNameInfo(3, 2);
        assertEq(trancheInfo.trancheName, "Senior Tranche");

        // Invalid tranche count
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.trancheNameInfo(0, 0);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.trancheNameInfo(1, 1);
    }

    function test_clearingPeriodLength() public {
        SystemVariablesSetup memory systemVariablesSetup = _initialize();
        assertEq(systemVariables.clearingPeriodLength(), systemVariablesSetup.clearingPeriodLength);
    }

    function test_performanceFee() public {
        SystemVariablesSetup memory systemVariablesSetup = _initialize();
        assertEq(systemVariables.performanceFee(), systemVariablesSetup.performanceFee);
    }

    function test_setPerformanceFee() public {
        _initialize();

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

    function test_setFeeRates() public {
        _initialize();

        uint256 newEcosystemFeeRate = 40_00;
        uint256 newProtocolFeeRate = 60_00;
        hoax(admin);
        systemVariables.setFeeRates(newEcosystemFeeRate, newProtocolFeeRate);

        (uint256 ecosystemFeeRate, uint256 protocolFeeRate) = systemVariables.feeRates();
        assertEq(ecosystemFeeRate, newEcosystemFeeRate);
        assertEq(protocolFeeRate, newProtocolFeeRate);

        // test revert invalid configuration
        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.setFeeRates(50_00, 50_01);

        // test revert no role
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        systemVariables.setFeeRates(newEcosystemFeeRate, newProtocolFeeRate);
    }

    function test_loyaltyThresholds() public {
        SystemVariablesSetup memory systemVariablesSetup = _initialize();

        uint256[] memory loyaltyThresholds = systemVariables.loyaltyThresholds();
        assertEq(loyaltyThresholds[0], systemVariablesSetup.loyaltyThresholds[0]);
        assertEq(loyaltyThresholds[1], systemVariablesSetup.loyaltyThresholds[1]);
    }

    function test_setLoyaltyThreshold() public {
        _initialize();

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
        _initialize();

        hoax(admin);
        systemVariables.setDefaultTrancheInterestChangeEpochDelay(2);

        assertEq(systemVariables.defaultTrancheInterestChangeEpochDelay(), 2);
    }

    function _initialize() internal returns (SystemVariablesSetup memory) {
        return _initialize(_getDefaultInitializeConfig());
    }

    function _initialize(SystemVariablesSetup memory systemVariablesSetup)
        internal
        returns (SystemVariablesSetup memory)
    {
        systemVariables.initialize(systemVariablesSetup);

        return systemVariablesSetup;
    }

    function _getDefaultInitializeConfig() internal view returns (SystemVariablesSetup memory systemVariablesSetup) {
        systemVariablesSetup.initialEpochStartTimestamp = block.timestamp;
        systemVariablesSetup.clearingPeriodLength = 1 days;
        systemVariablesSetup.performanceFee = 10_00;
        systemVariablesSetup.loyaltyThresholds = new uint256[](2);
        systemVariablesSetup.loyaltyThresholds[0] = 1_00;
        systemVariablesSetup.loyaltyThresholds[1] = 3_00;
        systemVariablesSetup.defaultTrancheInterestChangeEpochDelay = 4;
        systemVariablesSetup.ecosystemFeeRate = 50_00;
        systemVariablesSetup.protocolFeeRate = 50_00;
        systemVariablesSetup.protocolFeeReceiver = address(0xfee);
    }
}
