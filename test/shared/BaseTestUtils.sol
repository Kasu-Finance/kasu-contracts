// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseTestUtils is Test {
    address internal admin = address(0xad);
    address internal alice = address(0xaaa);
    address internal bob = address(0xbbb);
    address internal carol = address(0xccc);
    address internal david = address(0xddd);

    function _approve(IERC20 token, address owner, address spender, uint256 amount) internal prank(owner) {
        token.approve(spender, amount);
    }

    function _prank(address executor) internal {
        if (executor.balance > 0) {
            vm.startPrank(executor);
        } else {
            startHoax(executor);
        }
    }

    modifier prank(address executor) {
        _prank(executor);
        _;
        vm.stopPrank();
    }
}
