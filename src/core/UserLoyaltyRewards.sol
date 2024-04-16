// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IUserLoyaltyRewards.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/access/KasuAccessControllable.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";

/**
 * @title User Loyalty Rewards Contract
 * @notice This contract is used to handle KSU rewards for users based on their active liquidity and loyalty level.
 */
contract UserLoyaltyRewards is IUserLoyaltyRewards, KasuAccessControllable, Initializable {
    using SafeERC20 for IERC20;

    /// @notice Maximum epoch reward rate.
    uint256 private constant MAX_REWARD_EPOCH_RATE = INTEREST_RATE_FULL_PERCENT / 20; // 5%

    /// @notice KSU token price contract.
    IKsuPrice private immutable _ksuPrice;

    /// @notice KSU token contract.
    IERC20 private immutable _ksuToken;

    /// @notice User manager contract.
    address private _userManager;

    /// @notice Flag to enable/disable rewards emission.
    bool public doEmitRewards;

    /// @notice Total unclaimed rewards of users.
    uint256 public totalUnclaimedRewards;

    /// @notice Mapping of loyalty level to reward rate per epoch.
    mapping(uint256 loyaltyLevel => uint256 epochRewardRate) public loyaltyEpochRewardRates;

    /// @notice Mapping of user to unclaimed reward amount.
    mapping(address user => uint256 rewardAmount) public userRewards;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor.
     * @param ksuPrice_ KSU token price contract.
     * @param ksuToken_ KSU token contract.
     * @param controller_ Kasu controller contract.
     */
    constructor(IKsuPrice ksuPrice_, IERC20 ksuToken_, IKasuController controller_)
        KasuAccessControllable(controller_)
    {
        AddressLib.checkIfZero(address(ksuPrice_));
        AddressLib.checkIfZero(address(ksuToken_));

        _ksuPrice = ksuPrice_;
        _ksuToken = ksuToken_;

        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract.
     * @param userManager_ User manager contract.
     * @param doEmitRewards_ Flag to enable/disable rewards emission.
     */
    function initialize(address userManager_, bool doEmitRewards_) external initializer {
        AddressLib.checkIfZero(address(userManager_));

        _userManager = userManager_;
        _setDoEmitRewards(doEmitRewards_);
    }

    /* ========== EXTERNAL MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Emits user loyalty rewards.
     * @dev Only user manager contract can call this function.
     * @param user User address.
     * @param epoch Epoch number.
     * @param userLoyaltyLevel User loyalty level.
     * @param amountDeposited Active amount deposited by user.
     */
    function emitUserLoyaltyReward(address user, uint256 epoch, uint256 userLoyaltyLevel, uint256 amountDeposited)
        external
    {
        if (!doEmitRewards) {
            return;
        }

        if (msg.sender != _userManager) {
            revert OnlyUserManager();
        }

        uint256 ksuTokenPrice = _ksuPrice.ksuTokenPrice();

        _emitUserLoyaltyReward(user, epoch, userLoyaltyLevel, amountDeposited, ksuTokenPrice);
    }

    /**
     * @notice Enables or disables rewards emission.
     * @param doEmitRewards_ Flag to enable/disable rewards emission.
     */
    function setDoEmitRewards(bool doEmitRewards_) external onlyAdmin {
        _setDoEmitRewards(doEmitRewards_);
    }

    /**
     * @notice Sets reward rates per loyalty level.
     * @param loyaltyEpochRewardRatesInput Array of loyalty level and reward rate per epoch.
     */
    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata loyaltyEpochRewardRatesInput)
        external
        onlyAdmin
    {
        for (uint256 i; i < loyaltyEpochRewardRatesInput.length; ++i) {
            if (loyaltyEpochRewardRatesInput[i].epochRewardRate > MAX_REWARD_EPOCH_RATE) {
                revert InvalidConfiguration();
            }

            loyaltyEpochRewardRates[loyaltyEpochRewardRatesInput[i].loyaltyLevel] =
                loyaltyEpochRewardRatesInput[i].epochRewardRate;

            emit UpdatedLoyaltyLevelRewardRate(
                loyaltyEpochRewardRatesInput[i].loyaltyLevel, loyaltyEpochRewardRatesInput[i].epochRewardRate
            );
        }
    }

    /**
     * @notice Emits user loyalty rewards for a batch of users.
     * @dev Only admin can call this function.
     * @param userRewardInputs Array of user reward details.
     * @param ksuTokenPrice KSU token price. Iz zero, the current price will be used.
     */
    function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata userRewardInputs, uint256 ksuTokenPrice)
        external
        onlyAdmin
    {
        if (ksuTokenPrice == 0) {
            ksuTokenPrice = _ksuPrice.ksuTokenPrice();
        }

        for (uint256 i; i < userRewardInputs.length; ++i) {
            _emitUserLoyaltyReward(
                userRewardInputs[i].user,
                userRewardInputs[i].epoch,
                userRewardInputs[i].userLoyaltyLevel,
                userRewardInputs[i].amountDeposited,
                ksuTokenPrice
            );
        }
    }

    /**
     * @notice Claims user reward.
     * @param amount Reward amount to claim. If value is more than user's reward, the full reward will be claimed.
     */
    function claimReward(uint256 amount) external {
        uint256 reward = userRewards[msg.sender];

        if (amount > reward) {
            amount = reward;
        }

        uint256 ksuBalance = _ksuToken.balanceOf(address(this));

        if (ksuBalance < amount) {
            amount = ksuBalance;
        }

        if (amount == 0) {
            return;
        }

        userRewards[msg.sender] -= amount;
        totalUnclaimedRewards -= amount;

        // transfer reward to user
        _ksuToken.safeTransfer(msg.sender, amount);

        emit UserRewardClaimed(msg.sender, amount);
    }

    /**
     * @notice Recovers ERC20 tokens.
     * @dev Only admin can call this function.
     * @param tokenAddress Token address.
     * @param tokenAmount Token amount.
     * @param recipient Recipient address.
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount, address recipient) external onlyAdmin {
        IERC20(tokenAddress).safeTransfer(recipient, tokenAmount);
    }

    /* ========== INTERNAL MUTATIVE FUNCTIONS ========== */

    function _setDoEmitRewards(bool doEmitRewards_) private {
        if (doEmitRewards == doEmitRewards_) {
            return;
        }

        doEmitRewards = doEmitRewards_;

        if (doEmitRewards_) {
            emit LoyaltyRewardsEnabled();
        } else {
            emit LoyaltyRewardsDisabled();
        }
    }

    function _emitUserLoyaltyReward(
        address user,
        uint256 epoch,
        uint256 userLoyaltyLevel,
        uint256 amountDeposited,
        uint256 ksuTokenPrice
    ) private {
        if (amountDeposited == 0 || ksuTokenPrice == 0) {
            return;
        }

        uint256 epochRewardRate = loyaltyEpochRewardRates[userLoyaltyLevel];

        if (epochRewardRate == 0) {
            return;
        }

        // calculate reward in KSU tokens based on user's active liquidity, epoch reward rate and KSU token price.
        uint256 ksuReward = (amountDeposited * epochRewardRate * KSU_PRICE_MULTIPLIER * 1e12) / ksuTokenPrice
            / INTEREST_RATE_FULL_PERCENT;

        userRewards[user] += ksuReward;
        totalUnclaimedRewards += ksuReward;

        emit UserLoyaltyRewardsEmitted(user, epoch, ksuReward);
    }
}
