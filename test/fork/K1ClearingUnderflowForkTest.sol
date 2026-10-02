// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/core/UserManager.sol";
import "../../src/core/lendingPool/LendingPoolTranche.sol";
import "../../src/core/interfaces/lendingPool/ILendingPoolManager.sol";
import "../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "../../src/core/interfaces/ISystemVariables.sol";

interface IERC721EnumerableLike {
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

interface IClearingCoordinatorViews {
    function nextLendingPoolClearingEpoch(address lendingPool) external view returns (uint256);
}

/**
 * @dev Base mainnet fork: the Tax Pay clearing underflow (K-1) on the live state, before and after the fix.
 *
 * Skipped unless `FORK=1`. RPC: `BASE_RPC_URL`, else the public Base RPC. Block: `FORK_BLOCK`, else latest.
 *   FORK=1 forge test --mc K1ClearingUnderflowForkTest -vv
 *
 * The stale request: 0x8498..7dF9 holds a 1-share Tax Pay Mezzanine withdrawal (epoch 67) while its active
 * tranche count is 0 (a 2025-08-29 zero-share `forceImmediateWithdrawal` on Senior decremented it twice).
 * Once another request ages into the same priority, accepting it underflows the count and reverts `doClearing`.
 */
contract K1ClearingUnderflowForkTest is Test {
    IERC20 private constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address private constant LPM = 0xE1Be322323a412579b4A09fB08ff4bfcA12096B5;
    address private constant SYS_VARS = 0x193Bb02A24F5562b58fEB86550e6f09Bb6c41f69;
    address private constant USER_MANAGER = 0x5Dc8D315a80fd99AbEF0f327B9a52a3FBC3C93f3;
    address private constant CLEARING = 0x2cF12A6d91fa4bEB5a4C17589a03e78F88f57DE2;
    address private constant KSU_LOCKING = 0xB145C061684C701c2C018A3f322aa14F5A553CE1;
    address private constant USER_LOYALTY_REWARDS = 0xB4784f69Bb1F1076F50907cB0a815908a719D635;
    address private constant FIXED_TERM_DEPOSIT = 0x757AB3139E09Beb9cCdf59762aD00825EfAE5ED3;
    address private constant TRANCHE_BEACON = 0xA2e9992B73BE340eC7134e751A4E5358374Fb1d0;

    address private constant POOL_SAFE = 0x7adf999af5E0617257014C94888cf98c4584E5E9; // Tax Pay clearing manager
    address private constant TAX_PAY = 0xc987350716Fe4a7d674C3591c391D29eBA26B8Ce;
    address private constant TAX_PAY_PP = 0x716042b7407022035f48A4Cd2d52D42b360a7a47;
    address private constant TAX_PAY_MEZZ = 0xe2024d80C5dCc1E2F552F7685B9E957Da3d2817E;
    address private constant TAX_PAY_SENIOR = 0x70c5Bc8D18366Fb7C190514dd9BBaff937Fe2F38;

    address private constant STALE_USER = 0x849878Fe831a83a3B265850149068e50d7687dF9;
    address private constant UNDERCOUNTED_USER = 0x20547cB8588bf3A1f531bB32EdAaF6e72BF9052C;
    address private constant EVICTED_SENIOR_1 = 0x0876eA886B818C4F30aaf4cE61949A7890De9c70;
    address private constant EVICTED_SENIOR_2 = 0x7b4A6F5FaD9aB79749EC7190Ec27BeAdD434A658;

    uint256 private constant COUNT_SLOT = 7;
    uint256 private constant USERS_SLOT = 6;

    ISystemVariables private constant sv = ISystemVariables(SYS_VARS);

    function setUp() public {
        if (!vm.envOr("FORK", false)) {
            vm.skip(true);
            return;
        }
        string memory rpc = vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org"));
        uint256 blockNumber = vm.envOr("FORK_BLOCK", uint256(0));
        if (blockNumber == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, blockNumber);
    }

    // ------------------------------------------------------------------ helpers

    function _count(address user) private view returns (uint256) {
        return uint256(vm.load(USER_MANAGER, keccak256(abi.encode(user, COUNT_SLOT))));
    }

    function _trancheUsersContain(address tranche, address user) private view returns (bool) {
        uint256 n = uint256(vm.load(tranche, bytes32(USERS_SLOT)));
        uint256 base = uint256(keccak256(abi.encode(USERS_SLOT)));
        for (uint256 i; i < n; ++i) {
            if (address(uint160(uint256(vm.load(tranche, bytes32(base + i))))) == user) return true;
        }
        return false;
    }

    function _staleWNft() private view returns (uint256) {
        IERC721EnumerableLike pp = IERC721EnumerableLike(TAX_PAY_PP);
        uint256 n = pp.balanceOf(STALE_USER);
        for (uint256 i; i < n; ++i) {
            uint256 id = pp.tokenOfOwnerByIndex(STALE_USER, i);
            if ((id >> 160) >= 2 ** 95) return id; // withdrawal NFT
        }
        return 0;
    }

    function _upgrade() private {
        UserManager umImpl = new UserManager(
            ISystemVariables(SYS_VARS), IKSULocking(KSU_LOCKING), IUserLoyaltyRewards(USER_LOYALTY_REWARDS)
        );
        ProxyAdmin pa = ProxyAdmin(address(uint160(uint256(vm.load(USER_MANAGER, ERC1967Utils.ADMIN_SLOT)))));
        vm.prank(pa.owner());
        pa.upgradeAndCall(ITransparentUpgradeableProxy(USER_MANAGER), address(umImpl), "");

        LendingPoolTranche trImpl = new LendingPoolTranche(
            IUserManager(USER_MANAGER), FIXED_TERM_DEPOSIT, ILendingPoolManager(LPM), address(USDC)
        );
        UpgradeableBeacon beacon = UpgradeableBeacon(TRANCHE_BEACON);
        vm.prank(beacon.owner());
        beacon.upgradeTo(address(trImpl));
    }

    function _warp(uint256 ts) private {
        vm.warp(ts);
        vm.roll(block.number + 1);
    }

    /// @dev Pays the owed fees and leaves `excess` USDC of pool excess (withdrawals are paid from excess only).
    function _repay(uint256 excess) private {
        uint256 amount = ILendingPool(TAX_PAY).feesOwedAmount() + excess;
        // FiatToken v2.2 packs the balance into `balanceAndBlacklistStates` (slot 9); stdStorage cannot find it
        vm.store(
            address(USDC), keccak256(abi.encode(POOL_SAFE, uint256(9))), bytes32(USDC.balanceOf(POOL_SAFE) + amount)
        );
        vm.startPrank(POOL_SAFE);
        USDC.approve(LPM, amount);
        ILendingPoolManager(LPM).repayOwedFunds(TAX_PAY, amount, POOL_SAFE);
        vm.stopPrank();
    }

    function _clearingCall() private returns (bool ok, bytes memory ret) {
        IClearingCoordinatorViews cc = IClearingCoordinatorViews(CLEARING);
        if (cc.nextLendingPoolClearingEpoch(TAX_PAY) > sv.currentEpochNumber()) {
            _warp(sv.nextEpochStartTimestamp() + 1 hours);
        }
        if (!sv.isClearingTime()) _warp(sv.nextEpochStartTimestamp() - sv.clearingPeriodLength() + 1 hours);
        UserManager(USER_MANAGER).batchCalculateUserLoyaltyLevels(10_000);

        uint256[] memory ratios = new uint256[](3);
        ratios[0] = 10_000; // the 100%-junior override kasu-clearing uses
        uint256 target = cc.nextLendingPoolClearingEpoch(TAX_PAY);
        vm.prank(POOL_SAFE);
        (ok, ret) = LPM.call(
            abi.encodeCall(
                ILendingPoolManager.doClearing,
                (
                    TAX_PAY,
                    target,
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max,
                    ClearingConfiguration(0, ratios, 0, 0),
                    true
                )
            )
        );
    }

    /// Clears the current epoch, then the next one with pool excess (the first clearing where another request
    /// shares the stale request's priority).
    function _clearTwoEpochs() private returns (bool ok, bytes memory ret) {
        (ok, ret) = _clearingCall();
        assertTrue(ok, "first clearing");
        _warp(sv.nextEpochStartTimestamp() + 1 hours);
        _repay(100e6);
        (ok, ret) = _clearingCall();
    }

    // ------------------------------------------------------------------ tests

    function test_fork_K1_liveCodeRevertsClearing() public {
        if (_staleWNft() == 0) return; // already cancelled or cleared on-chain
        (bool ok, bytes memory ret) = _clearTwoEpochs();
        assertFalse(ok, "live code: clearing reverts");
        assertEq(ret, abi.encodeWithSignature("Panic(uint256)", 0x11));
    }

    function test_fork_K1_fixedCodeClears() public {
        uint256 wNft = _staleWNft();
        if (wNft == 0) return;
        _upgrade();

        vm.recordLogs();
        (bool ok,) = _clearTwoEpochs();
        assertTrue(ok, "fixed code: clearing succeeds");

        bool underflowEmitted;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == USER_MANAGER
                    && logs[i].topics[0] == IUserManager.UserActiveTrancheCountUnderflow.selector
                    && logs[i].topics[1] == bytes32(uint256(uint160(STALE_USER)))
            ) underflowEmitted = true;
        }
        assertTrue(underflowEmitted, "skipped decrement is surfaced as an event");
        assertEq(_staleWNft(), 0, "stale request accepted");
        assertEq(ILendingPoolTranche(TAX_PAY_MEZZ).userActiveShares(STALE_USER), 0);
        assertEq(_count(STALE_USER), 0);
    }

    /// The repair the upgrade ships with: put the two evicted Senior holders back, fix the undercounted user.
    function test_fork_repairDesyncedState() public {
        _upgrade();

        assertFalse(_trancheUsersContain(TAX_PAY_SENIOR, EVICTED_SENIOR_1));
        assertFalse(_trancheUsersContain(TAX_PAY_SENIOR, EVICTED_SENIOR_2));
        ILendingPoolTranche(TAX_PAY_SENIOR).syncTrancheUser(EVICTED_SENIOR_1);
        ILendingPoolTranche(TAX_PAY_SENIOR).syncTrancheUser(EVICTED_SENIOR_2);
        assertTrue(_trancheUsersContain(TAX_PAY_SENIOR, EVICTED_SENIOR_1));
        assertTrue(_trancheUsersContain(TAX_PAY_SENIOR, EVICTED_SENIOR_2));

        address[] memory users = new address[](2);
        uint256[] memory counts = new uint256[](2);
        (users[0], counts[0]) = (UNDERCOUNTED_USER, 2);
        (users[1], counts[1]) = (STALE_USER, ILendingPoolTranche(TAX_PAY_MEZZ).userActiveShares(STALE_USER) > 0 ? 1 : 0);
        ProxyAdmin pa = ProxyAdmin(address(uint160(uint256(vm.load(USER_MANAGER, ERC1967Utils.ADMIN_SLOT)))));
        address impl = address(uint160(uint256(vm.load(USER_MANAGER, ERC1967Utils.IMPLEMENTATION_SLOT))));
        vm.prank(pa.owner());
        pa.upgradeAndCall(
            ITransparentUpgradeableProxy(USER_MANAGER),
            impl,
            abi.encodeCall(UserManager.setUserActiveTrancheCounts, (users, counts))
        );
        assertEq(_count(UNDERCOUNTED_USER), 2);
        assertEq(_count(STALE_USER), counts[1]);

        // and the clearing still goes through with the repaired state
        (bool ok,) = _clearTwoEpochs();
        assertTrue(ok, "clearing after repair");
    }
}
