// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IKsuPrice.sol";
import "../../vendor/chainsight/IOracle.sol";
import "../shared/AddressLib.sol";

contract KsuPrice is IKsuPrice {
    IOracle public immutable oracle;
    address public immutable oracleSender;

    constructor(IOracle oracle_, address oracleSender_) {
        AddressLib.checkIfZero(address(oracle_));
        AddressLib.checkIfZero(oracleSender_);

        oracle = oracle_;
        oracleSender = oracleSender_;
    }

    function getKsuTokenPrice() external view returns (uint256) {
        return oracle.readAsUint256(oracleSender);
    }
}
