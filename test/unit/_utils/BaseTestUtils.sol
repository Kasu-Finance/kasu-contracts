// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

abstract contract BaseTestUtils is Test {
    address internal admin = address(0xad1);

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal carol = address(0x3);
    address internal david = address(0x4);
    address internal userFive = address(0x5);
    address internal userSix = address(0x6);
    address internal userSeven = address(0x7);
    address internal userEight = address(0x8);
    address internal userNine = address(0x9);
    address internal userTen = address(0xA);

    address internal userNotAllowed = address(0x5);

    ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

    function test_baseUtils() external pure {}

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
