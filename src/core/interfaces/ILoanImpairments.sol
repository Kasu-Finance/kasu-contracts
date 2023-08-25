// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

interface ILoanImpairments is IERC1155Upgradeable {
    function claim() external;
    function issueImpairmentReceipts() external returns (uint256[] memory);
}
