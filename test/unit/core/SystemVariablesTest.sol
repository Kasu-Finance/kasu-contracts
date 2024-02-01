// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/Test.sol";
import {BaseTestUtils} from "../../shared/BaseTestUtils.sol";
import "../../../src/core/SystemVariables.sol";
import "../../../src/shared/CommonErrors.sol";
import "../../shared/MockKsuPrice.sol";

contract SystemVariablesTest is BaseTestUtils {
    SystemVariables internal systemVariables;
    MockKsuPrice internal ksuPrice;
    IKasuController internal kasuController;

    function setUp() public {
        ksuPrice = new MockKsuPrice();
        kasuController = IKasuController(address(0xcccc));

        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

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

    function test_getPriceUpdateEpoch() public {
        _initalize();
        assertEq(systemVariables.getPriceUpdateEpoch(), 0);

        skip(8 days);
        assertEq(systemVariables.getPriceUpdateEpoch(), 0);

        systemVariables.updateKsuEpochTokenPrice();
        assertEq(systemVariables.getPriceUpdateEpoch(), 1);
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

    function test_protocolFee() public {
        SystemVariablesSetup memory systemVariablesSetup = _initalize();
        assertEq(systemVariables.protocolFee(), systemVariablesSetup.protocolFee);
    }

    function test_setProtocolFee() public {
        _initalize();

        uint256 newProtocolFee = 20_00;
        hoax(admin);
        systemVariables.setProtocolFee(newProtocolFee);

        assertEq(systemVariables.protocolFee(), newProtocolFee);

        // test revert invalid configuration
        hoax(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidConfiguration.selector));
        systemVariables.setProtocolFee(100_01);

        // test revert no role
        hoax(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ROLE_KASU_ADMIN)
        );
        systemVariables.setProtocolFee(newProtocolFee);
    }

    function _initalize() internal returns (SystemVariablesSetup memory systemVariablesSetup) {
        systemVariablesSetup = SystemVariablesSetup(block.timestamp, 1 days, 10_00);
        systemVariables.initialize(systemVariablesSetup);
    }
}
