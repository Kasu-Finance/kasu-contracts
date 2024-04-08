// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./CommonErrors.sol";

/**
 * @dev Collection of functions related to the address type
 */
library AddressLib {
    function checkIfZero(address addressToCheck) internal pure {
        if (addressToCheck == address(0)) {
            revert ConfigurationAddressZero();
        }
    }
}
