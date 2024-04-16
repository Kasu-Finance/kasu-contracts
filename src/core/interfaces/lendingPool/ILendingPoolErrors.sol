// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface ILendingPoolErrors {
    error InvalidLendingPool(address lendingPool);
    error InvalidTranche(address lendingPool, address tranche);
    error OnlyOwnLendingPool(address sender, address ownLendingPool);
    error OnlyOwnPendingPool(address sender, address ownPendingPool);
    error OnlyLendingPoolManager();
    error OnlyClearingCoordinator();
    error LendingPoolIsStopped();
    error LendingPoolIsNotStopped();
}
