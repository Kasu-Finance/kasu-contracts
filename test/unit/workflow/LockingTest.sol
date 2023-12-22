// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TestFixture} from "../../shared/TestFixture.sol";
import "../../../src/token/KSU.sol";
import "../../shared/MockERC20Permit.sol";

contract LockingTest is TestFixture {

    function setup() public {
        ProxyAdmin proxy = new ProxyAdmin(admin);
        KSU ksuImpl = new KSU();
        TransparentUpgradeableProxy ksuProxy =
                    new TransparentUpgradeableProxy(address(ksuImpl), address(proxy), "");
        KSU _ksu = KSU(address(ksuProxy));
        _ksu.initialize(address(admin));

        MockERC20Permit _usdc = new MockERC20Permit("USDC", "USDC", 6);
        setupBase(ERC20Permit(address(_ksu)), _usdc);
    }

    function testCase1() public  {
        
    }
}
