// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./interfaces/IKsuPrice.sol";
import "../../vendor/chainsight/IOracle.sol";
import "../shared/AddressLib.sol";

/**
 * @title KSU token price contract
 * @notice This contract is used to get the current price of the KSU token using Chainsight oracle.
 */
contract KsuPrice is IKsuPrice {
    /// @notice Chainsight oracle contract.
    IOracle public immutable oracle;
    /// @notice Address of the oracle sender.
    address public immutable oracleSender;

    /**
     * @notice Constructor.
     * @param oracle_ Chainsight oracle contract.
     * @param oracleSender_ Address of the oracle sender.
     */
    constructor(IOracle oracle_, address oracleSender_) {
        AddressLib.checkIfZero(address(oracle_));
        AddressLib.checkIfZero(oracleSender_);

        oracle = oracle_;
        oracleSender = oracleSender_;
    }

    /**
     * @notice Get the current price of the KSU token.
     * @return Price of the KSU token.
     */
    function getKsuTokenPrice() external view returns (uint256) {
        return oracle.readAsUint256(oracleSender);
    }
}
