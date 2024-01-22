// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolTranche.sol";
import "../interfaces/lendingPool/IPendingPool.sol";
import "../interfaces/lendingPool/ILendingPool.sol";
import "../AssetFunctionsBase.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPool is ILendingPool, ERC20Upgradeable, AssetFunctionsBase {
    LendingPoolInfo private _lendingPoolInfo;
    mapping(address => bool) public isTranche;

    constructor(address underlyingAsset_) AssetFunctionsBase(underlyingAsset_) {}

    function initialize(string memory name_, string memory symbol_, LendingPoolInfo memory lendingPoolInfo_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);

        // TODO: setup the lending pool and it's tranches
        _lendingPoolInfo.pendingPool = lendingPoolInfo_.pendingPool;

        for (uint256 i; i < lendingPoolInfo_.tranches.length; i++) {
            _lendingPoolInfo.tranches.push(lendingPoolInfo_.tranches[i]);
            address tranche = lendingPoolInfo_.tranches[i].trancheAddress;
            isTranche[tranche] = true;

            approve(tranche, type(uint256).max);
        }
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function lendingPoolInfo() external view returns (LendingPoolInfo memory) {
        return _lendingPoolInfo;
    }

    function getPendingPool() external view returns (address) {
        return _lendingPoolInfo.pendingPool;
    }

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

        address user = IPendingPool(_lendingPoolInfo.pendingPool).ownerOf(dNftID);

        // accept deposit and receive assets from the pending pool
        IPendingPool(_lendingPoolInfo.pendingPool).acceptDepositRequest(dNftID, acceptedAmount);

        // mint the same amount as the accepted deposit
        _mint(address(this), acceptedAmount);

        // deposit the minted tokens to the tranche
        ILendingPoolTranche(tranche).deposit(acceptedAmount, user);
    }

    function acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) external {
        address tranche = address(uint160(wNftID));
        if (!isTranche[tranche]) {
            revert("LendingPool: invalid tranche");
        }

        address user = IPendingPool(_lendingPoolInfo.pendingPool).ownerOf(wNftID);

        // accept deposit and receive assets from the pending pool
        IPendingPool(_lendingPoolInfo.pendingPool).acceptWithdrawalRequest(wNftID, acceptedShares);

        // deposit the minted tokens to the tranche
        uint256 lendingPoolToken = ILendingPoolTranche(tranche).redeem(acceptedShares, address(this), address(this));

        // transfer assets to the user
        _transferAssets(user, lendingPoolToken);

        // burn the lending pool token
        _burn(address(this), lendingPoolToken);
    }

    function _acceptUserWithdrawal(address tranche, address user, uint256 shares) internal {
        uint256 assets = ILendingPoolTranche(tranche).redeem(shares, address(this), user);
        _burn(address(this), assets);

        // TODO: move withdrawn assets to the user
    }
}
