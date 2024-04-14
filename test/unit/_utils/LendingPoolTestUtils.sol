// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Test.sol";
import "./BaseTestUtils.sol";
import "../../shared/MockKsuPrice.sol";
import "../../../src/core/lendingPool/LendingPoolManager.sol";
import "../../../src/core/lendingPool/LendingPoolFactory.sol";
import "../../../src/core/SystemVariables.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import "../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import "../../../src/shared/access/KasuController.sol";
import "../../../src/core/interfaces/lendingPool/ILendingPoolManager.sol";
import "../../../src/core/UserManager.sol";
import "../../../src/core/UserLoyaltyRewards.sol";
import "./LockingTestUtils.sol";
import "../../../src/core/KasuAllowList.sol";
import "../../../src/core/clearing/AcceptedRequestsCalculation.sol";
import "../../../src/core/FeeManager.sol";
import "../../../src/core/Swapper.sol";
import "../../shared/MockExchange.sol";
import "../../shared/ArraysUtil.sol";
import {WETH9} from "../../shared/MockWeth.sol";

abstract contract LendingPoolTestUtils is LockingTestUtils {
    ILendingPoolManager internal lendingPoolManager;
    IKasuController internal kasuController;
    MockKsuPrice internal ksuPrice;
    IUserLoyaltyRewards internal userLoyaltyRewards;
    ISystemVariables internal systemVariables;
    IUserManager internal userManager;
    IKasuAllowList internal kasuAllowList;
    ILendingPoolFactory internal lendingPoolFactory;
    IFeeManager internal feeManager;
    IClearingCoordinator internal clearingCoordinator;
    ISwapper internal swapper;
    WETH9 internal weth;

    mapping(address => PendingPoolHarness) internal pendingPools;

    address internal poolFundsManagerAccount = address(0xad2);
    address internal lendingPoolCreatorAccount = address(0xad3);
    address internal lendingPoolAdminAccount = address(0xad4);
    address internal poolManagerAccount = address(0xad5);
    address internal poolClearingManagerAccount = address(0xad5);

    address internal feeReceiverAccount = address(0xfee);

    function __lendingPool_setUp() internal {
        // fund accounts
        vm.deal(admin, 1 << 128);
        vm.deal(alice, 1 << 128);
        vm.deal(bob, 1 << 128);
        vm.deal(carol, 1 << 128);
        vm.deal(david, 1 << 128);
        vm.deal(user5, 1 << 128);
        vm.deal(user6, 1 << 128);
        vm.deal(user7, 1 << 128);
        vm.deal(user8, 1 << 128);
        vm.deal(user9, 1 << 128);
        vm.deal(user10, 1 << 128);
        vm.deal(user11, 1 << 128);
        vm.deal(user12, 1 << 128);
        vm.deal(user13, 1 << 128);
        vm.deal(user14, 1 << 128);
        vm.deal(user15, 1 << 128);
        vm.deal(user16, 1 << 128);
        vm.deal(user17, 1 << 128);
        vm.deal(user18, 1 << 128);
        vm.deal(user19, 1 << 128);
        vm.deal(user20, 1 << 128);
        vm.deal(userNotAllowed, 1 << 128);

        // access control - setup
        KasuController kasuControllerImpl = new KasuController();
        TransparentUpgradeableProxy kasuControllerProxy =
            new TransparentUpgradeableProxy(address(kasuControllerImpl), address(proxyAdmin), "");
        kasuController = KasuController(address(kasuControllerProxy));

        // allow list
        KasuAllowList KasuAllowListImpl = new KasuAllowList(kasuController);
        TransparentUpgradeableProxy KasuAllowListProxy =
            new TransparentUpgradeableProxy(address(KasuAllowListImpl), address(proxyAdmin), "");
        kasuAllowList = IKasuAllowList(address(KasuAllowListProxy));

        // ksu price
        _deployKsuPrice();

        // system variables
        _deploySystemVariables();

        // fee manager
        FeeManager feeManagerImpl = new FeeManager(address(mockUsdc), systemVariables, kasuController, _KSULocking);
        TransparentUpgradeableProxy feeManagerProxy =
            new TransparentUpgradeableProxy(address(feeManagerImpl), address(proxyAdmin), "");
        feeManager = IFeeManager(address(feeManagerProxy));

        // user loyalty rewards
        UserLoyaltyRewards userLoyaltyRewardsImpl = new UserLoyaltyRewards(ksuPrice, _ksu, kasuController);
        TransparentUpgradeableProxy userLoyaltyRewardsProxy =
            new TransparentUpgradeableProxy(address(userLoyaltyRewardsImpl), address(proxyAdmin), "");
        userLoyaltyRewards = UserLoyaltyRewards(address(userLoyaltyRewardsProxy));

        // user manager
        UserManager userManagerImpl = new UserManager(systemVariables, _KSULocking, userLoyaltyRewards);
        TransparentUpgradeableProxy userManagerProxy =
            new TransparentUpgradeableProxy(address(userManagerImpl), address(proxyAdmin), "");
        userManager = UserManager(address(userManagerProxy));

        UserLoyaltyRewards(address(userLoyaltyRewards)).initialize(address(userManager), true);

        // lending pool manager
        swapper = new Swapper(kasuController);
        weth = new WETH9();
        LendingPoolManager lendingPoolManagerImpl =
            new LendingPoolManager(address(mockUsdc), kasuController, IWETH9(address(weth)), swapper);
        TransparentUpgradeableProxy lendingPoolManagerProxy =
            new TransparentUpgradeableProxy(address(lendingPoolManagerImpl), address(proxyAdmin), "");
        lendingPoolManager = LendingPoolManager(address(lendingPoolManagerProxy));

        UserManager(address(userManager)).initialize(address(lendingPoolManager));

        // clearing
        AcceptedRequestsCalculation acceptedRequestsCalculationImpl = new AcceptedRequestsCalculation();
        TransparentUpgradeableProxy acceptedRequestsCalculationProxy =
            new TransparentUpgradeableProxy(address(acceptedRequestsCalculationImpl), address(proxyAdmin), "");
        IAcceptedRequestsCalculation acceptedRequestsCalculation =
            IAcceptedRequestsCalculation(address(acceptedRequestsCalculationProxy));

        // clearing

        ClearingCoordinator clearingCoordinatorImpl =
            new ClearingCoordinator(systemVariables, userManager, lendingPoolManager);
        TransparentUpgradeableProxy clearingManagerProxy =
            new TransparentUpgradeableProxy(address(clearingCoordinatorImpl), address(proxyAdmin), "");
        clearingCoordinator = IClearingCoordinator(address(clearingManagerProxy));

        // pending pool
        PendingPool pendingPoolIml = new PendingPoolHarness(
            systemVariables,
            address(mockUsdc),
            lendingPoolManager,
            userManager,
            clearingCoordinator,
            acceptedRequestsCalculation
        );
        UpgradeableBeacon pendingPoolBeacon = new UpgradeableBeacon(address(pendingPoolIml), admin);
        // lending pool
        LendingPool lendingPoolImp = new LendingPool(
            systemVariables, address(lendingPoolManager), clearingCoordinator, feeManager, address(mockUsdc)
        );
        UpgradeableBeacon lendingPoolBeacon = new UpgradeableBeacon(address(lendingPoolImp), admin);
        // lending pool tranche
        LendingPoolTranche lendingPoolTrancheImp = new LendingPoolTranche(lendingPoolManager, address(mockUsdc));
        UpgradeableBeacon lendingPoolTrancheBeacon = new UpgradeableBeacon(address(lendingPoolTrancheImp), admin);
        // lending pool factory
        LendingPoolFactory lendingPoolFactoryImpl = new LendingPoolFactory(
            address(pendingPoolBeacon),
            address(lendingPoolBeacon),
            address(lendingPoolTrancheBeacon),
            kasuController,
            address(lendingPoolManager),
            systemVariables
        );
        TransparentUpgradeableProxy lendingPoolFactoryProxy =
            new TransparentUpgradeableProxy(address(lendingPoolFactoryImpl), address(proxyAdmin), "");
        lendingPoolFactory = LendingPoolFactory(address(lendingPoolFactoryProxy));

        // access control - init
        KasuController(address(kasuController)).initialize(admin, address(lendingPoolFactory));

        LendingPoolManager(address(lendingPoolManager)).initialize(
            lendingPoolFactory, kasuAllowList, userManager, clearingCoordinator
        );

        vm.startPrank(admin);
        kasuController.grantRole(ROLE_SWAPPER, address(lendingPoolManager));
        vm.stopPrank();

        // kasu allow list - allow users
        vm.startPrank(admin);
        kasuAllowList.allowUser(alice);
        kasuAllowList.allowUser(bob);
        kasuAllowList.allowUser(carol);
        kasuAllowList.allowUser(david);
        kasuAllowList.allowUser(user5);
        kasuAllowList.allowUser(user6);
        kasuAllowList.allowUser(user7);
        kasuAllowList.allowUser(user8);
        kasuAllowList.allowUser(user9);
        kasuAllowList.allowUser(user10);
        kasuAllowList.allowUser(user11);
        kasuAllowList.allowUser(user12);
        kasuAllowList.allowUser(user13);
        kasuAllowList.allowUser(user14);
        kasuAllowList.allowUser(user15);
        kasuAllowList.allowUser(user16);
        kasuAllowList.allowUser(user17);
        kasuAllowList.allowUser(user18);
        kasuAllowList.allowUser(user19);
        kasuAllowList.allowUser(user20);

        LoyaltyEpochRewardRateInput[] memory loyaltyEpochRewardRatesInput = new LoyaltyEpochRewardRateInput[](2);
        loyaltyEpochRewardRatesInput[0] = LoyaltyEpochRewardRateInput(1, 38329912069265);
        loyaltyEpochRewardRatesInput[1] = LoyaltyEpochRewardRateInput(2, 19164956034632);
        userLoyaltyRewards.setRewardRatesPerLoyaltyLevel(loyaltyEpochRewardRatesInput);
        vm.stopPrank();
    }

    function _allowUser(address user) internal prank(admin) {
        kasuAllowList.allowUser(user);
    }

    function _deployKsuPrice() internal {
        MockKsuPrice ksuPriceImpl = new MockKsuPrice();
        TransparentUpgradeableProxy ksuPriceProxy =
            new TransparentUpgradeableProxy(address(ksuPriceImpl), address(proxyAdmin), "");
        ksuPrice = MockKsuPrice(address(ksuPriceProxy));

        // set price
        ksuPrice.setKsuTokenPrice(2e18);
    }

    function _deploySystemVariables() internal {
        SystemVariables systemVariablesImpl = new SystemVariables(ksuPrice, kasuController);
        TransparentUpgradeableProxy systemVariablesProxy =
            new TransparentUpgradeableProxy(address(systemVariablesImpl), address(proxyAdmin), "");
        systemVariables = SystemVariables(address(systemVariablesProxy));

        // initialize
        SystemVariablesSetup memory systemVariablesSetup;
        systemVariablesSetup.firstEpochStartTimestamp = block.timestamp;
        systemVariablesSetup.clearingPeriodLength = 1 days;
        systemVariablesSetup.performanceFee = 10_00;
        systemVariablesSetup.loyaltyThresholds = new uint256[](2);
        systemVariablesSetup.loyaltyThresholds[0] = 1_00;
        systemVariablesSetup.loyaltyThresholds[1] = 3_00;
        systemVariablesSetup.ecosystemFeeRate = 50_00;
        systemVariablesSetup.protocolFeeRate = 50_00;
        systemVariablesSetup.protocolFeeReceiver = feeReceiverAccount;

        SystemVariables(address(systemVariables)).initialize(systemVariablesSetup);
    }

    function _createLendingPool(CreatePoolConfig memory createPoolConfig)
        private
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        lendingPoolDeployment = lendingPoolManager.createPool(createPoolConfig);
        pendingPools[lendingPoolDeployment.lendingPool] = PendingPoolHarness(address(lendingPoolDeployment.pendingPool));
        // fund lending pool
        vm.deal(lendingPoolDeployment.lendingPool, 1 << 128);
    }

    // ###  Helper Functions ###

    function _createDefaultLendingPool() internal returns (LendingPoolDeployment memory lendingPoolDeployment) {
        // create lending
        uint256 minDepositAmount = 10 * 1e6;
        uint256 maxDepositAmount = 1_000_000 * 1e6;
        uint256 targetExcessLiquidityPercentage = 10_00;
        uint256 minExcessLiquidityPercentage = 0;
        uint256 desiredDrawAmount = 600_000 * 1e6;
        CreateTrancheConfig[] memory createTrancheConfig = new CreateTrancheConfig[](3);
        createTrancheConfig[0] = CreateTrancheConfig(10_00, 2500000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[1] = CreateTrancheConfig(20_00, 2000000000000000, minDepositAmount, maxDepositAmount);
        createTrancheConfig[2] = CreateTrancheConfig(70_00, 1500000000000000, minDepositAmount, maxDepositAmount);
        CreatePoolConfig memory createPoolConfig = CreatePoolConfig(
            "Test Lending Pool",
            "TLP",
            targetExcessLiquidityPercentage,
            minExcessLiquidityPercentage,
            createTrancheConfig,
            lendingPoolAdminAccount,
            poolFundsManagerAccount,
            desiredDrawAmount
        );
        return _createLendingPoolFromConfig(createPoolConfig);
    }

    function _createLendingPoolFromConfig(CreatePoolConfig memory createPoolConfig)
        internal
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        // access control - grant
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreatorAccount);
        // create lending pool
        vm.prank(lendingPoolCreatorAccount);
        lendingPoolDeployment = _createLendingPool(createPoolConfig);
        // access control - grant
        vm.startPrank(createPoolConfig.poolAdmin);
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_POOL_FUNDS_MANAGER, poolFundsManagerAccount
        );
        kasuController.grantLendingPoolRole(lendingPoolDeployment.lendingPool, ROLE_POOL_MANAGER, poolManagerAccount);
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_POOL_CLEARING_MANAGER, poolClearingManagerAccount
        );
        vm.stopPrank();
    }

    function _createMockExchange(uint256 rate) internal returns (address exchange, address inToken) {
        MockERC20Permit tokenA = new MockERC20Permit("TokenB", "TKB", 18);
        MockExchange mockExchange = new MockExchange(address(tokenA), address(mockUsdc), rate);

        deal(address(mockUsdc), address(mockExchange), 1_000_000_000 * 1e6);
        deal(address(tokenA), address(mockExchange), 1_000_000 ether);

        return (address(mockExchange), address(tokenA));
    }

    // USER

    function _requestDeposit(address sender, address lendingPool, address tranche, uint256 amount)
        internal
        prank(sender)
        returns (uint256 dNftId)
    {
        deal(address(mockUsdc), sender, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        return lendingPoolManager.requestDeposit(lendingPool, tranche, amount, "");
    }

    function _cancelDepositRequest(address sender, address lendingPool, uint256 dNftId) internal prank(sender) {
        lendingPoolManager.cancelDepositRequest(lendingPool, dNftId);
    }

    function _requestWithdrawal(address sender, address lendingPool, address tranche, uint256 amount)
        internal
        prank(sender)
        returns (uint256 wNftId)
    {
        return lendingPoolManager.requestWithdrawal(lendingPool, tranche, amount);
    }

    function _cancelWithdrawalRequest(address sender, address lendingPool, uint256 wNftId) internal prank(sender) {
        lendingPoolManager.cancelWithdrawalRequest(lendingPool, wNftId);
    }

    // CLEARING

    function _acceptDepositRequest(address lendingPool, uint256 dNftID, uint256 acceptedShares) internal {
        pendingPools[lendingPool].acceptDepositRequest(dNftID, acceptedShares);
    }

    function _acceptWithdrawalRequest(address lendingPool, uint256 wNftID, uint256 acceptedShares) internal {
        pendingPools[lendingPool].acceptWithdrawalRequest(wNftID, acceptedShares);
    }

    // POOL DELEGATE

    function _drawFunds(address lendingPool, uint256 amount) internal prank(address(clearingCoordinator)) {
        ILendingPool(lendingPool).drawFunds(amount);
    }

    function _repayOwedFunds(address caller, address repaymentAddress, address lendingPool, uint256 amount) internal {
        deal(address(mockUsdc), repaymentAddress, amount, true);
        vm.prank(repaymentAddress);
        mockUsdc.approve(address(lendingPoolManager), amount);
        vm.prank(caller);
        lendingPoolManager.repayOwedFunds(lendingPool, amount, repaymentAddress);
    }

    function _depositFirstLossCapital(address caller, address lendingPool, uint256 amount) internal prank(caller) {
        deal(address(mockUsdc), caller, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        lendingPoolManager.depositFirstLossCapital(lendingPool, amount);
    }

    function _withdrawFirstLossCapital(address caller, address lendingPool, uint256 amount, address withdrawAddress)
        internal
        prank(caller)
    {
        lendingPoolManager.withdrawFirstLossCapital(lendingPool, amount, withdrawAddress);
    }

    function _forceImmediateWithdrawal(
        address caller,
        address lendingPool,
        address tranche,
        address user,
        uint256 shares
    ) internal prank(caller) {
        lendingPoolManager.forceImmediateWithdrawal(lendingPool, tranche, user, shares);
    }

    function _batchForceWithdrawals(address caller, address lendingPool, ForceWithdrawalInput[] memory input)
        internal
        prank(caller)
        returns (uint256[] memory)
    {
        return lendingPoolManager.batchForceWithdrawals(lendingPool, input);
    }

    function _stop(address caller, address lendingPool) internal prank(caller) {
        lendingPoolManager.stopLendingPool(lendingPool);
    }

    function _reportLoss(address caller, address lendingPool, uint256 amount, bool doMintLossTokens)
        internal
        prank(caller)
        returns (uint256)
    {
        return lendingPoolManager.reportLoss(lendingPool, amount, doMintLossTokens);
    }

    function _repayLoss(address caller, address lendingPool, address tranche, uint256 lossId, uint256 amount)
        internal
        prank(caller)
    {
        deal(address(mockUsdc), caller, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        lendingPoolManager.repayLoss(lendingPool, tranche, lossId, amount);
    }

    function _claimRepaidLoss(address caller, address lendingPool, address tranche, uint256 lossId)
        internal
        prank(caller)
        returns (uint256 claimedAmount)
    {
        return lendingPoolManager.claimRepaidLoss(lendingPool, tranche, lossId);
    }

    function _doClearing(
        address caller,
        address lendingPool,
        uint256 targetEpoch,
        uint256 pendingRequestsPriorityCalculationBatchSize,
        uint256 acceptedRequestsExecutionBatchSize,
        ClearingConfiguration memory clearingConfig,
        bool isConfigOverridden
    ) internal prank(caller) {
        lendingPoolManager.doClearing(
            lendingPool,
            targetEpoch,
            pendingRequestsPriorityCalculationBatchSize,
            acceptedRequestsExecutionBatchSize,
            clearingConfig,
            isConfigOverridden
        );
    }

    function test_mockLendingPoolTestUtils() public pure {}
}

contract PendingPoolHarness is PendingPool {
    constructor(
        ISystemVariables systemVariables_,
        address underlyingAsset_,
        ILendingPoolManager lendingPoolManager_,
        IUserManager userManger_,
        IClearingCoordinator clearingCoordinator_,
        IAcceptedRequestsCalculation acceptedRequestsCalculation_
    )
        PendingPool(
            systemVariables_,
            underlyingAsset_,
            lendingPoolManager_,
            userManger_,
            clearingCoordinator_,
            acceptedRequestsCalculation_
        )
    {}

    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external {
        (address tranche,) = UserRequestIds.decomposeDepositId(dNftID);
        return _acceptDepositRequest(dNftID, tranche, acceptedAmount);
    }

    function acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) external {
        return _acceptWithdrawalRequest(wNftID, acceptedShares);
    }
}
