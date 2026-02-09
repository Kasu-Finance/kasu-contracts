// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "../../../src/shared/AddressLib.sol";

contract AddressLibWrapper {
    function checkIfZero(address addressToCheck) external pure {
        AddressLib.checkIfZero(addressToCheck);
    }
}

contract AddressLibTest is Test {
    AddressLibWrapper wrapper;

    function setUp() public {
        wrapper = new AddressLibWrapper();
    }

    function test_checkIfZero() public {
        vm.expectRevert(abi.encodeWithSelector(ConfigurationAddressZero.selector));
        wrapper.checkIfZero(address(0));
    }

    function test_checkIfZero_nonZeroAddress() public view {
        wrapper.checkIfZero(address(1));
    }
}
