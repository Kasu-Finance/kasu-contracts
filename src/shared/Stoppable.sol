// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

abstract contract Stoppable {
    bool public isStopped;

    function _stop() internal {
        isStopped = true;
    }

    modifier shouldNotBeStopped() {
        if (isStopped) {
            revert ContractIsStopped();
        }
        _;
    }

    error ContractIsStopped();
}
