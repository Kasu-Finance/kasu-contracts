// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPool is ERC20Upgradeable {
    struct LendingPoolInfo {
        TrancheData juniorTranche;
        TrancheData mezzoTranche;
        TrancheData seniorTranche;
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

    function initialize(string memory name_, string memory symbol_) public initializer {
        __ERC20_init(name_, symbol_);

        // TODO: setup the lending pool and it's tranches
    }

    LendingPoolInfo public lendingPoolInfo;

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function getTrancheBalance(address trancheAddress) external view returns (uint256) {
        return lendingPoolInfo.juniorTranche.balance;
    }

    function acceptDepositRequest(address tranche, uint256 dNftID) external {}

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
