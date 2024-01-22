// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";

struct LendingPoolInfo {
    TrancheData[] tranches;
    address pendingPool;
    uint256 firstLossCapital;
    uint256 totalBalance;
    uint256 excessFunds;
    uint256 excessTargetLiquidity; // percentage of not borrowed funds (only as senior deposits)
}

struct TrancheData {
    address trancheAddress;
    uint256 balance;
    uint256 interestRate;
}

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPool is ERC20Upgradeable {

    LendingPoolInfo private _lendingPoolInfo;
    mapping(address => bool) public isTranche;

    function initialize(string memory name_, string memory symbol_, LendingPoolInfo memory lendingPoolInfo_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);

        // TODO: setup the lending pool and it's tranches
        _lendingPoolInfo = lendingPoolInfo_;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function lendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    // TODO: update accordingly
    function getTrancheBalance(address tranche) external view returns (uint256) {
        if (!isTranche[tranche]) {
            revert("LendingPool: invalid tranche");
        }

        return ILendingPoolTranche(tranche).totalAssets();
    }

    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external {
        address tranche = address(uint160(dNftID));
        if (!isTranche[tranche]) {
            revert("LendingPool: invalid tranche");
        }

        IPendingPool pendingPool = IPendingPool(tranche);

        address user = pendingPool.ownerOf(dNftID);

        // accept deposit and receive assets from the pending pool
        IPendingPool(_lendingPoolInfo.pendingPool).acceptDepositRequest(dNftID, acceptedAmount);

        // mint the same amount as the accepted deposit
        _mint(address(this), acceptedAmount);
        // deposit the minted tokens to the tranche
        pendingPool.deposit(acceptedAmount, user);
    }

    function _acceptUserDeposit(address tranche, address user, uint256 amount) internal {
        // TODO: move deposit pending funds to the lending pool

        _mint(address(this), amount);

        ILendingPoolTranche(tranche).deposit(amount, user);
    }

    function _acceptUserWithdrawal(address tranche, address user, uint256 shares) internal {
        uint256 assets = ILendingPoolTranche(tranche).redeem(shares, address(this), user);
        _burn(address(this), assets);

        // TODO: move withdrawn assets to the user
    }
}
