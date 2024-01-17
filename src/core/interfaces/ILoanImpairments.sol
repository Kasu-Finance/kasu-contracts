// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface ILoanImpairments is IERC1155 {
    function claim() external;

    function issueImpairmentReceipts(
        address lendingPool,
        address tranche,
        address[] calldata users,
        uint256[] calldata shares
    ) external;
}
