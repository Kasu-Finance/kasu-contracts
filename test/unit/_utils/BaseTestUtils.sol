// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../shared/MockUSDC.sol";

abstract contract BaseTestUtils is Test {
    MockUSDC internal mockUsdc;

    address internal admin = address(0xad1);

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal carol = address(0x3);
    address internal david = address(0x4);
    address internal user5 = address(0x5);
    address internal user6 = address(0x6);
    address internal user7 = address(0x7);
    address internal user8 = address(0x8);
    address internal user9 = address(0x9);
    address internal user10 = address(0xA);
    address internal user11 = address(0xB);
    address internal user12 = address(0xC);
    address internal user13 = address(0xD);
    address internal user14 = address(0xE);
    address internal user15 = address(0xF);
    address internal user16 = address(0x10);
    address internal user17 = address(0x11);
    address internal user18 = address(0x12);
    address internal user19 = address(0x13);
    address internal user20 = address(0x14);

    address internal userNotAllowed = address(0x15);

    ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

    function __baseTestUtils_setUp() internal {
        // usdc
        MockUSDC mockUsdcImpl = new MockUSDC();
        TransparentUpgradeableProxy mockUsdcProxy =
            new TransparentUpgradeableProxy(address(mockUsdcImpl), address(proxyAdmin), "");
        mockUsdc = MockUSDC(address(mockUsdcProxy));
        mockUsdc.initialize();
    }

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
