// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract MockUSDC is ERC20PermitUpgradeable {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;

    function initialize() external initializer {
        __ERC20_init("USDC Token", "USDC");
        __ERC20Permit_init("USDC Token");
    }

    function test_mock() external pure {}

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
