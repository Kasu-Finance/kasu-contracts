// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/shared/AddressLib.sol";

contract AddressLibTest is Test {
    function test_checkIfZero() public {
        vm.expectRevert(abi.encodeWithSelector(ConfigurationAddressZero.selector));
        AddressLib.checkIfZero(address(0));
    }
}
