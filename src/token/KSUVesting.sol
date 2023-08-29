// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "@openzeppelin/utils/Address.sol";
import "@openzeppelin/utils/Context.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

/* ========== ERRORS ========== */
/**
 * @notice Used when payees and shares array are not same length.
 */

error PayeesAndSharesLengthMismatch();
/**
 * @notice Used when payees provided.
 */

error NoPayeesProvided();
/**
 * @notice Used when start date is not set in the future.
 */

error StartDateMustBeNonZeroValue();
/**
 * @notice Used when duration is set to zero.
 */
error DurationMustBeNonZeroValue();

/**
 * @notice Used when account has no shares.
 */
error AccountHasNoShares();

/**
 * @notice Used when account is not due payment
 */
error AccountNotDuePayment();

/**
 * @notice Used when account is the zero address
 */
error AccountZeroAddress();

/**
 * @notice Used when payee shares are zero
 */
error PayeeSharesZero();

/**
 * @notice Used when account already has shares
 */
error AccountPayeeSharesAlreadySet();

/**
 * @title VestingSplitter
 */
contract KSUVesting is Context {
    event PayeeAdded(address account, uint256 shares);
    event PaymentReleased(IERC20 indexed token, address to, uint256 amount);

    IERC20 public token;

    uint256 private _vestedAtStart;
    uint256 private _totalShares;
    uint256 private _totalReleased;

    mapping(address => uint256) private _released;
    mapping(address => uint256) private _shares;

    address[] private _payees;

    uint256 private immutable _start;
    uint256 private immutable _duration;

    /**
     * @dev Creates an instance of `VestingSplitter` where each account in `payees` is assigned the number of shares at
     * the matching position in the `shares` array.
     *
     * All addresses in `payees` must be non-zero. Both arrays must have the same non-zero length, and there must be no
     * duplicates in `payees`.
     */
    constructor(
        uint256 startTimestamp,
        uint256 durationSeconds,
        IERC20 token_,
        address[] memory payees,
        uint256[] memory shares_,
        uint256 vestedAtStart_
    ) {
        if (durationSeconds == 0) revert DurationMustBeNonZeroValue();
        if (startTimestamp == 0) revert StartDateMustBeNonZeroValue();
        if (payees.length != shares_.length) revert PayeesAndSharesLengthMismatch();
        if (payees.length == 0) revert NoPayeesProvided();

        _start = startTimestamp;
        _duration = durationSeconds;
        _vestedAtStart = vestedAtStart_;
        token = token_;

        for (uint256 i = 0; i < payees.length; ++i) {
            _addPayee(payees[i], shares_[i]);
        }
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start() external view returns (uint256) {
        return _start;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration() external view returns (uint256) {
        return _duration;
    }

    /**
     * @dev Calculates the amount of KSU tokens that has already vested.
     * Default implementation is a linear vesting curve.
     */
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        // TODO: handle scenario where tokens haven't been sent to the vesting contract yet
        return _vestingSchedule(IERC20(token).balanceOf(address(this)) + _totalReleased - _vestedAtStart, timestamp)
            + _vestedAtStart;
    }

    /**
     * @notice Returns amount that can be released based on amount vested in vesting wallet
     */
    function releasable(address account) public view returns (uint256) {
        uint256 totalReceived = vestedAmount(uint64(block.timestamp));

        return (totalReceived * _shares[account]) / _totalShares - _released[account];
    }

    /**
     * @dev Getter for the total shares held by payees.
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @dev Getter for the total amount of KSU already released.
     */
    function totalReleased() external view returns (uint256) {
        return _totalReleased;
    }

    /**
     * @dev Getter for the amount of shares held by an account.
     */
    function shares(address account) external view returns (uint256) {
        return _shares[account];
    }

    /**
     * @dev Getter for the amount of KSU tokens already released to a payee.
     * @param account Beneficiary
     */
    function released(address account) external view returns (uint256) {
        return _released[account];
    }

    /**
     * @dev Getter for the address of the payee number `index`.
     */
    function payee(uint256 index) external view returns (address) {
        return _payees[index];
    }

    /**
     * @dev Triggers a transfer to `account` of the amount of `token` tokens they are owed, according to their
     * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
     * contract.
     */
    function release(address account) external {
        if (_shares[account] == 0) revert AccountHasNoShares();

        uint256 payment = releasable(account);

        if (payment == 0) revert AccountNotDuePayment();

        // _erc20TotalReleased[token] is the sum of all values in _erc20Released[token].
        // If "_erc20TotalReleased[token] += payment" does not overflow, then "_erc20Released[token][account] += payment"
        // cannot overflow.
        _totalReleased += payment;

        unchecked {
            _released[account] += payment;
        }

        SafeERC20.safeTransfer(token, account, payment);
        emit PaymentReleased(token, account, payment);
    }

    /**
     * @dev Add a new payee to the contract.
     * @param account The address of the payee to add.
     * @param shares_ The number of shares owned by the payee.
     */
    function _addPayee(address account, uint256 shares_) private {
        if (account == address(0)) revert AccountZeroAddress();
        if (shares_ == 0) revert PayeeSharesZero();
        if (_shares[account] != 0) revert AccountPayeeSharesAlreadySet();

        _payees.push(account);
        _shares[account] = shares_;
        _totalShares += shares_;
        emit PayeeAdded(account, shares_);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) private view returns (uint256) {
        if (timestamp < _start) {
            return 0;
        } else if (timestamp > _start + _duration) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - _start)) / _duration;
        }
    }
}
