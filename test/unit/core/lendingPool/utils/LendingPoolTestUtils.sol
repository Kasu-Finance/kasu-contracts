// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/Test.sol";
import "../../../../shared/MockUSDC.sol";
import "../../../../../src/core/lendingPool/LendingPoolManager.sol";
import "../../../../../src/core/lendingPool/LendingPoolFactory.sol";
import "../../../../../src/core/KsuPrice.sol";
import "../../../../../src/core/SystemVariables.sol";
import "../../../../../src/core/interfaces/lendingPool/ILendingPoolFactory.sol";
import "../../../../../src/core/interfaces/lendingPool/IPendingPool.sol";
import {BaseTestUtils} from "../../../../shared/BaseTestUtils.sol";
import "../../../../../src/shared/access/KasuController.sol";
import "../../../../shared/MockKsuPrice.sol";
import "../../../../../src/core/interfaces/lendingPool/ILendingPoolManager.sol";

abstract contract LendingPoolTestUtils is BaseTestUtils {
    ProxyAdmin internal proxyAdmin;
    LendingPoolManager internal lendingPoolManager;
    KasuController internal kasuController;
    KsuPrice internal ksuPrice;
    SystemVariables internal systemVariables;
    MockUSDC internal mockUsdc;
    mapping(address => PendingPoolHarness) internal pendingPools;

    LendingPoolFactory private lendingPoolFactory;

    address internal lendingPoolLoanAdmin = address(0xad2);
    address internal lendingPoolCreator = address(0xad3);
    address internal lendingPoolAdmin = address(0xad4);
    address internal admin5 = address(0xad4);

    function __lendingPool_setUp() internal {
        // fund accounts
        vm.deal(admin, 1 << 128);
        vm.deal(alice, 1 << 128);
        vm.deal(bob, 1 << 128);

        // proxy admin
        proxyAdmin = new ProxyAdmin(admin);

        // usdc
        {
            MockUSDC mockUsdcImpl = new MockUSDC();
            TransparentUpgradeableProxy mockUsdcProxy =
                new TransparentUpgradeableProxy(address(mockUsdcImpl), address(proxyAdmin), "");
            mockUsdc = MockUSDC(address(mockUsdcProxy));
            mockUsdc.initialize(admin);
        }

        // access control - setup
        KasuController kasuControllerImpl = new KasuController();
        TransparentUpgradeableProxy kasuControllerProxy =
            new TransparentUpgradeableProxy(address(kasuControllerImpl), address(proxyAdmin), "");
        kasuController = KasuController(address(kasuControllerProxy));

        // ksu price
        _deployKsuPrice();

        // system variables
        _deploySystemVariables();

        // lending pool manager
        LendingPoolManager lendingPoolManagerImpl = new LendingPoolManager(address(mockUsdc), kasuController);
        TransparentUpgradeableProxy lendingPoolManagerProxy =
            new TransparentUpgradeableProxy(address(lendingPoolManagerImpl), address(proxyAdmin), "");
        lendingPoolManager = LendingPoolManager(address(lendingPoolManagerProxy));

        // pending pool
        PendingPool pendingPoolIml = new PendingPoolHarness(address(mockUsdc), lendingPoolManager);
        UpgradeableBeacon pendingPoolBeacon = new UpgradeableBeacon(address(pendingPoolIml), admin);
        // lending pool
        LendingPool lendingPoolImp = new LendingPool(systemVariables, address(mockUsdc));
        UpgradeableBeacon lendingPoolBeacon = new UpgradeableBeacon(address(lendingPoolImp), admin);
        // lending pool tranche
        LendingPoolTranche lendingPoolTrancheImp = new LendingPoolTranche(lendingPoolManager);
        UpgradeableBeacon lendingPoolTrancheBeacon = new UpgradeableBeacon(address(lendingPoolTrancheImp), admin);
        // lending pool factory
        LendingPoolFactory lendingPoolFactoryImpl = new LendingPoolFactory(
            address(pendingPoolBeacon),
            address(lendingPoolBeacon),
            address(lendingPoolTrancheBeacon),
            kasuController,
            lendingPoolManager
        );
        TransparentUpgradeableProxy lendingPoolFactoryProxy =
            new TransparentUpgradeableProxy(address(lendingPoolFactoryImpl), address(proxyAdmin), "");
        lendingPoolFactory = LendingPoolFactory(address(lendingPoolFactoryProxy));

        // access control - init
        kasuController.initialize(admin, address(lendingPoolFactory));
        lendingPoolManager.initialize(lendingPoolFactory);
    }

    function _deployKsuPrice() internal {
        MockKsuPrice ksuPriceImpl = new MockKsuPrice();
        TransparentUpgradeableProxy ksuPriceProxy =
            new TransparentUpgradeableProxy(address(ksuPriceImpl), address(proxyAdmin), "");
        ksuPrice = KsuPrice(address(ksuPriceProxy));

        ksuPrice.initialize();
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
        systemVariablesSetup.protocolFee = 10_00;
        systemVariablesSetup.loyaltyThresholds = new uint256[](2);
        systemVariablesSetup.loyaltyThresholds[0] = 1_00;
        systemVariablesSetup.loyaltyThresholds[1] = 3_00;

        systemVariables.initialize(systemVariablesSetup);
    }

    function createLendingPool(PoolConfiguration memory poolConfiguration)
        internal
        returns (LendingPoolDeployment memory lendingPoolDeployment)
    {
        lendingPoolDeployment = lendingPoolManager.createPool(poolConfiguration);
        pendingPools[lendingPoolDeployment.lendingPool] = PendingPoolHarness(address(lendingPoolDeployment.pendingPool));
        // fund lending pool
        vm.deal(lendingPoolDeployment.lendingPool, 1 << 128);
    }

    // ###  Helper Functions ###

    function _createDefaultLendingPool() internal returns (LendingPoolDeployment memory lendingPoolDeployment) {
        // access control - grant
        vm.prank(admin);
        kasuController.grantRole(ROLE_LENDING_POOL_CREATOR, lendingPoolCreator);
        // create lending
        uint256 minDepositAmount = 1 ether;
        uint256 targetExcessLiquidity = 50_000 * 1e6;
        Tranches memory tranches;
        tranches.junior = TrancheDetail(true, 10, 20);
        tranches.mezzo = TrancheDetail(true, 20, 10);
        tranches.senior = TrancheDetail(true, 70, 5);
        PoolConfiguration memory poolConfiguration = PoolConfiguration(
            "Test Lending Pool",
            "TLP",
            address(mockUsdc),
            minDepositAmount,
            targetExcessLiquidity,
            tranches,
            lendingPoolAdmin,
            lendingPoolLoanAdmin
        );
        vm.prank(lendingPoolCreator);
        lendingPoolDeployment = createLendingPool(poolConfiguration);
        // access control - grant
        vm.prank(lendingPoolAdmin);
        kasuController.grantLendingPoolRole(
            lendingPoolDeployment.lendingPool, ROLE_LENDING_POOL_LOAN_MANAGER, lendingPoolLoanAdmin
        );
    }

    // USER

    function _requestDeposit(address sender, address lendingPool, address tranche, uint256 amount)
        internal
        prank(sender)
        returns (uint256 dNftId)
    {
        deal(address(mockUsdc), sender, amount, true);
        // TODO: approve pendingPool, even though we cannot query it ?? gas
        mockUsdc.approve(address(lendingPoolManager), amount);
        return lendingPoolManager.requestDeposit(lendingPool, tranche, amount);
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

    function _borrowLoan(address caller, address lendingPool, uint256 amount) internal prank(caller) {
        lendingPoolManager.borrowLoan(lendingPool, amount);
    }

    function _repayLoan(address caller, address repaymentAddress, address lendingPool, uint256 amount) internal {
        deal(address(mockUsdc), repaymentAddress, amount, true);
        vm.prank(repaymentAddress);
        mockUsdc.approve(lendingPool, amount);
        vm.prank(caller);
        lendingPoolManager.repayLoan(lendingPool, amount, repaymentAddress);
    }

    function _depositFirstLossCapital(address caller, address lendingPool, uint256 amount) internal prank(caller) {
        deal(address(mockUsdc), caller, amount, true);
        mockUsdc.approve(address(lendingPoolManager), amount);
        lendingPoolManager.depositFirstLossCapital(lendingPool, amount);
    }

    function _withdrawFirstLossCapital(address caller, address withdrawAddress, address lendingPool, uint256 amount)
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

    function _stop(address caller, address lendingPool, address firstLostCapitalReceiver) internal prank(caller) {
        lendingPoolManager.stopLendingPool(lendingPool, firstLostCapitalReceiver);
    }
}

contract PendingPoolHarness is PendingPool {
    constructor(address underlyingAsset_, ILendingPoolManager lendingPoolManager_)
        PendingPool(underlyingAsset_, lendingPoolManager_)
    {}

    function acceptDepositRequest(uint256 dNftID, uint256 acceptedAmount) external {
        return _acceptDepositRequest(dNftID, acceptedAmount);
    }

    function acceptWithdrawalRequest(uint256 wNftID, uint256 acceptedShares) external {
        return _acceptWithdrawalRequest(wNftID, acceptedShares);
    }
}
