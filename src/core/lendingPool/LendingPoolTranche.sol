// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "../interfaces/lendingPool/ILendingPoolErrors.sol";
import "../../shared/CommonErrors.sol";
import "./LendingPoolHelpers.sol";

/**
 * @dev
 * - assuming lower tier tranches cannot be used to exit higher level tranches
 * - when depositing, users receive IERC1155 deposit NFTs
 * - when withdrawing, users receive IERC1155 withdrawal NFTs
 * - when deposits are cleared, users receive ERC20 receipt tokens
 * - when withdrawals are cleared, users can claim assets using their withdrawal NFTs
 */
contract LendingPoolTranche is ERC4626Upgradeable, ERC1155Upgradeable, ILendingPoolErrors, LendingPoolHelpers {
    /// @dev user => nftIDs[]
    mapping(address => uint256[]) private userDepositNFTs;

    /// @dev user => nftIDs[]
    mapping(address => uint256[]) private userWithdrawalNFTs;

    mapping(address => bool) private isTrancheUser;

    address[] private trancheUsers;

    constructor(ILendingPoolManager lendingPoolManager_) LendingPoolHelpers(lendingPoolManager_) {}

    /**
     * @param name_ The name of the lending pool tranche token
     * @param symbol_ The symbol of the lending pool tranche token
     * @param asset_ Lending pool token
     */
    function initialize(string memory name_, string memory symbol_, IERC20 asset_) public initializer {
        __ERC20_init(name_, symbol_);
        __ERC4626_init(asset_);
        __ERC1155_init("");
    }

    function deposit(uint256 assets, address receiver) public override onlyOwnLendingPool returns (uint256) {
        if (isTrancheUser[receiver] == false) {
            isTrancheUser[receiver] = true;
            trancheUsers.push(receiver);
        }

        return super.deposit(assets, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyOwnLendingPool
        returns (uint256)
    {
        // NOTE: make sure the shares are not pending withdrawal or possibly lick the pending withdrawal amount
        if (balanceOf(receiver) == 0) {
            isTrancheUser[receiver] = false;
            // TODO: remove from the array
            // maybe by adding an id to each user in the trancheUsers array
        }

        return super.redeem(shares, receiver, owner);
    }

    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert NotSupported();
    }

    function mint(uint256, address) public pure override returns (uint256) {
        revert NotSupported();
    }
}
