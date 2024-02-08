// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";

contract ErrorInArray is Test {
    // this works ok
    function test_errorInArray() public {
        vm.expectRevert(abi.encodeWithSelector(FakeError.selector));
        errorInArray();
    }

    function errorInArray() internal pure returns (uint256[] memory wNftIDs) {
        wNftIDs = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            wNftIDs[i] = functionThatReverts(i);
        }
        console2.log(wNftIDs.length);
    }

    function functionThatReverts(uint256 i) internal pure returns (uint256) {
        if (i == 2) revert FakeError();
        return i;
    }

    error FakeError();
}
