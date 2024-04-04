// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../shared/access/KasuAccessControllable.sol";
import "./interfaces/IUserLoyaltyRewards.sol";
import "./interfaces/IKsuPrice.sol";
import "../shared/CommonErrors.sol";
import "../shared/AddressLib.sol";
import "./Constants.sol";

contract UserLoyaltyRewards is IUserLoyaltyRewards, KasuAccessControllable, Initializable {
    uint256 private constant MAX_REWARD_EPOCH_RATE = INTEREST_RATE_FULL_PERCENT / 20; // 5%

    IKsuPrice public immutable ksuPrice;
    IERC20 public immutable ksuToken;
    address public userManager;

    bool public doEmitRewards;

    uint256 public totalUnclaimedRewards;

    mapping(uint256 loyaltyLevel => uint256 epochRewardRate) public loyaltyEpochRewardRates;
    mapping(address user => uint256 rewardAmount) public userRewards;

    constructor(IKsuPrice ksuPrice_, IERC20 ksuToken_, IKasuController controller_)
        KasuAccessControllable(controller_)
    {
        AddressLib.checkIfZero(address(ksuPrice_));
        AddressLib.checkIfZero(address(ksuToken_));

        ksuPrice = ksuPrice_;
        ksuToken = ksuToken_;

        _disableInitializers();
    }

    function initialize(address userManager_, bool doEmitRewards_) external initializer {
        AddressLib.checkIfZero(address(userManager_));

        userManager = userManager_;
        _setDoEmitRewards(doEmitRewards_);
    }

    function setDoEmitRewards(bool doEmitRewards_) external onlyAdmin {
        _setDoEmitRewards(doEmitRewards_);
    }

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

    function setRewardRatesPerLoyaltyLevel(LoyaltyEpochRewardRateInput[] calldata loyaltyEpochRewardRatesInput)
        external
        onlyAdmin
    {
        for (uint256 i; i < loyaltyEpochRewardRatesInput.length; i++) {
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

    function recoverERC20(address tokenAddress, uint256 tokenAmount, address recipient) external onlyAdmin {
        IERC20(tokenAddress).transfer(recipient, tokenAmount);
    }

    function emitUserLoyaltyRewardBatch(UserRewardInput[] calldata userRewardInputs, uint256 ksuTokenPrice)
        external
        onlyAdmin
    {
        if (ksuTokenPrice == 0) {
            ksuTokenPrice = ksuPrice.getKsuTokenPrice();
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

    function emitUserLoyaltyReward(address user, uint256 epoch, uint256 userLoyaltyLevel, uint256 amountDeposited)
        external
    {
        if (!doEmitRewards) {
            return;
        }

        if (msg.sender != userManager) {
            revert OnlyUserManager();
        }

        uint256 ksuTokenPrice = ksuPrice.getKsuTokenPrice();

        _emitUserLoyaltyReward(user, epoch, userLoyaltyLevel, amountDeposited, ksuTokenPrice);
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

        uint256 ksuReward = (amountDeposited * epochRewardRate * KSU_PRICE_MULTIPLIER * 1e12) / ksuTokenPrice
            / INTEREST_RATE_FULL_PERCENT;

        userRewards[user] += ksuReward;
        totalUnclaimedRewards += ksuReward;

        emit UserLoyaltyRewardsEmitted(user, epoch, ksuReward);
    }

    function claimReward(uint256 amount) external {
        uint256 reward = userRewards[msg.sender];

        if (amount > reward) {
            amount = reward;
        }

        uint256 ksuBalance = ksuToken.balanceOf(address(this));

        if (ksuBalance < amount) {
            amount = ksuBalance;
        }

        if (amount == 0) {
            return;
        }

        userRewards[msg.sender] -= amount;
        totalUnclaimedRewards -= amount;

        // transfer reward to user
        ksuToken.transfer(msg.sender, amount);

        emit UserRewardClaimed(msg.sender, amount);
    }
}
