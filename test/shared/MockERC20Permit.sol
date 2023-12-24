// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20Permit is ERC20Permit {
    uint8 private _decimals = 18;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20Permit(name_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
