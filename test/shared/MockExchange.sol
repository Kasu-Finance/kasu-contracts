// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockExchange {
    using SafeERC20 for ERC20;

    ERC20 source;
    ERC20 target;

    uint256 immutable ratePrecision = 100_00;
    uint256 sourceDecimals;
    uint256 targetDecimals;
    uint256 rate; // source/target in 100_00

    constructor(address source_, address target_, uint256 rate_) {
        source = ERC20(source_);
        target = ERC20(target_);
        sourceDecimals = source.decimals();
        targetDecimals = target.decimals();
        rate = rate_;
    }

    function test_mock() external pure {}

    function swap(uint256 amount, address recipient) external returns (uint256) {
        uint256 out;
        if (targetDecimals > sourceDecimals) {
            out = amount * (10 ** (targetDecimals - sourceDecimals)) * rate / ratePrecision;
        } else {
            out = amount * rate / 10 ** (sourceDecimals - targetDecimals) / ratePrecision;
        }

        source.safeTransferFrom(msg.sender, address(this), amount);
        target.safeTransfer(recipient, out);

        return out;
    }
}
