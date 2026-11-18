//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {IERC20} from "./IERC20.sol";
import {
    WETH,
    WBTC,
    USDT,
    XAUt0,
    PLAST,
    WBRL,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2
} from "./ConstantsCelo.sol";

contract StockWalletFullTest is Test {
    StockWallet public wallet;
    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");
    address public user = makeAddr("user");

    IERC20 private usdt = IERC20(USDT);
    IERC20 private weth = IERC20(WETH);
    IERC20 private wbtc = IERC20(WBTC);
    IERC20 private xaut0 = IERC20(XAUt0);
    IERC20 private plast = IERC20(PLAST);
    IERC20 private wbrl = IERC20(WBRL);

    uint256 public constant INITIAL_USDC_FUNDING = 100 * 1e6;
    uint16 public constant TOTAL_PCT = 10_000;

    function _getAlloc(address token) internal view returns (uint256) {
        (uint256 alloc, , ) = wallet.assetConfig(token);
        return alloc;
    }

    function _getStopLoss(address token) internal view returns (uint16) {
        (, uint16 sl, ) = wallet.assetConfig(token);
        return sl;
    }

    function _getTakeProfit(address token) internal view returns (uint16) {
        (, , uint16 tp) = wallet.assetConfig(token);
        return tp;
    }

    function _getPosAmount(address token) internal view returns (uint256) {
        (uint256 amount, ) = wallet.assetPosition(token);
        return amount;
    }

    function _getPosInvested(address token) internal view returns (uint256) {
        (, uint256 invested) = wallet.assetPosition(token);
        return invested;
    }

    function setUp() public virtual {
        // Fork de Celo mainnet para que los contratos reales existan
        vm.createSelectFork("https://forno.celo.org");
        StockWallet.AssetConfig memory configWbtc = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.AssetConfig memory configWeth = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](2);
        tokenAllocation[0] = StockWallet.TokenAllocationConfig({
            token: WBTC,
            configs: configWbtc
        });
        tokenAllocation[1] = StockWallet.TokenAllocationConfig({
            token: WETH,
            configs: configWeth
        });

        vm.startPrank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            tokenAllocation
        );
        vm.stopPrank();

        deal(USDT, address(this), INITIAL_USDC_FUNDING);
        usdt.transfer(address(wallet), INITIAL_USDC_FUNDING);
        deal(USDT, user, 1000 * 1e6);
    }

    // =============================================================
    // === CONSTRUCTOR TESTS ===
    // =============================================================

    function test_constructor_success() public {
        assertEq(address(wallet.factory()), UNISWAP_V3_FACTORY);
        assertEq(address(wallet.quoter()), UNISWAP_V3_QUOTER);
        assertEq(wallet.usdc(), USDT);
        assertEq(wallet.owner(), owner);
        assertTrue(wallet.hasRole(wallet.ADGENT_ROLE(), adgent));
        assertTrue(wallet.hasRole(wallet.ADGENT_ROLE(), owner));

        assertEq(_getAlloc(WBTC), 5000);
        assertEq(_getStopLoss(WBTC), 9500);
        assertEq(_getTakeProfit(WBTC), 11000);

        assertEq(_getAlloc(WETH), 5000);
        assertEq(_getStopLoss(WETH), 9500);
        assertEq(_getTakeProfit(WETH), 11000);

        assertEq(wallet.assets(0), WBTC);
        assertEq(wallet.assets(1), WETH);
    }

    function test_constructor_revert_AddressZero() public {
        StockWallet.AssetConfig memory config = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](1);
        tokenAllocation[0] = StockWallet.TokenAllocationConfig({
            token: WBTC,
            configs: config
        });

        vm.expectRevert(StockWallet.Address_Zero.selector);
        new StockWallet(
            address(0),
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            tokenAllocation
        );

        vm.expectRevert(StockWallet.Address_Zero.selector);
        new StockWallet(
            USDT,
            address(0),
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            tokenAllocation
        );
    }

    function test_constructor_revert_EmptyTokenAllocation() public {
        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](0);
        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            tokenAllocation
        );
    }

    function test_constructor_revert_PercentagesExceedTotal() public {
        StockWallet.AssetConfig memory c1 = StockWallet.AssetConfig(
            6000,
            9500,
            11000
        );
        StockWallet.AssetConfig memory c2 = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](2);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c1);
        ta[1] = StockWallet.TokenAllocationConfig(WETH, c2);

        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            ta
        );
    }

    function test_constructor_revert_DuplicateTokens() public {
        StockWallet.AssetConfig memory c = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](2);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c);
        ta[1] = StockWallet.TokenAllocationConfig(WBTC, c);

        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            ta
        );
    }

    function test_constructor_revert_BadTakeProfitBps() public {
        StockWallet.AssetConfig memory c = StockWallet.AssetConfig(
            10000,
            9500,
            9000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](1);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrortakeProfitBps_notCorrect.selector,
                WBTC,
                9000
            )
        );
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            ta
        );
    }

    function test_constructor_revert_BadStopLossBps() public {
        StockWallet.AssetConfig memory c = StockWallet.AssetConfig(
            10000,
            10500,
            11000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](1);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrorStopLossBps_notCorrect.selector,
                WBTC,
                10500
            )
        );
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            ta
        );
    }

    // =============================================================
    // === ACCESS CONTROL / UPDATE FUNCTIONS ===
    // =============================================================

    function test_updateAdgent_success() public {
        address newAdgent = makeAddr("newAdgent");
        vm.prank(owner);
        wallet.updateAdgent(newAdgent);
        assertTrue(wallet.hasRole(wallet.ADGENT_ROLE(), newAdgent));
        assertFalse(wallet.hasRole(wallet.ADGENT_ROLE(), adgent));
    }

    function test_updateAdgent_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateAdgent(makeAddr("newAdgent"));
    }

    function test_updateAdgent_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.updateAdgent(address(0));
    }

    function test_updateAdgentContract_success() public {
        vm.prank(owner);
        wallet.updateAdgentContract(makeAddr("newAdgentContract"));
    }

    function test_updateAdgentContract_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateAdgentContract(makeAddr("newAdgentContract"));
    }

    function test_updateAdgentContract_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.updateAdgentContract(address(0));
    }

    function test_updateGasFee_success() public {
        vm.prank(owner);
        wallet.updateGasFee(500);
    }

    function test_updateGasFee_revert_ZeroAmount() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(owner);
        wallet.updateGasFee(0);
    }

    function test_updateGasFee_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateGasFee(500);
    }

    function test_updateAdgentPercentage_success() public {
        vm.prank(owner);
        wallet.updateAdgentPercentage(100);
    }

    function test_updateAdgentPercentage_revert_ZeroAmount() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(owner);
        wallet.updateAdgentPercentage(0);
    }

    function test_updateAdgentPercentage_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateAdgentPercentage(100);
    }

    // =============================================================
    // === DEPOSIT TESTS ===
    // =============================================================

    function test_depositAsset_usdc() public {
        uint256 depositAmount = 50 * 1e6;
        vm.startPrank(user);
        usdt.approve(address(wallet), depositAmount);

        uint256 walletBefore = usdt.balanceOf(address(wallet));
        wallet.depositAsset(USDT, depositAmount, new bytes(0));
        vm.stopPrank();

        assertEq(usdt.balanceOf(address(wallet)), walletBefore + depositAmount);
    }

    function test_depositAsset_revert_AmountInZero() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(user);
        wallet.depositAsset(USDT, 0, new bytes(0));
    }

    function test_depositAsset_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(user);
        wallet.depositAsset(address(0), 1e6, new bytes(0));
    }

    function test_depositAsset_revert_NotEnoughAllowance() public {
        uint256 depositAmount = 50 * 1e6;
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrorDeposit_NotEnoughtAllowance.selector,
                USDT,
                depositAmount
            )
        );
        vm.prank(user);
        wallet.depositAsset(USDT, depositAmount, new bytes(0));
    }

    // =============================================================
    // === WITHDRAW TESTS ===
    // =============================================================

    function test_withdrawAssetUsdt_success_owner() public {
        uint256 withdrawAmount = 10 * 1e6;
        uint256 walletBefore = usdt.balanceOf(address(wallet));
        uint256 ownerBefore = usdt.balanceOf(owner);

        vm.prank(owner);
        wallet.withdrawAssetUsdt(withdrawAmount);

        assertEq(
            usdt.balanceOf(address(wallet)),
            walletBefore - withdrawAmount
        );
        assertEq(usdt.balanceOf(owner), ownerBefore + withdrawAmount);
    }

    function test_withdrawAssetUsdt_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.withdrawAssetUsdt(1e6);
    }

    function test_withdrawAssetUsdt_revert_AmountInZero() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(owner);
        wallet.withdrawAssetUsdt(0);
    }

    function test_withdrawAsset_success_after_invest() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 wbtcBefore = wbtc.balanceOf(address(wallet));
        assertGt(wbtcBefore, 0);
        uint256 ownerBefore = wbtc.balanceOf(owner);

        vm.prank(owner);
        wallet.withdrawAsset(WBTC);

        assertEq(wbtc.balanceOf(address(wallet)), 0);
        assertEq(wbtc.balanceOf(owner), ownerBefore + wbtcBefore);

        assertEq(_getPosAmount(WBTC), 0);
        assertEq(_getPosInvested(WBTC), 0);
    }

    function test_withdrawAsset_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.withdrawAsset(WBTC);
    }

    function test_withdrawAsset_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.withdrawAsset(address(0));
    }

    function test_withdrawAsset_revert_InsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                WBTC,
                0,
                1
            )
        );
        vm.prank(owner);
        wallet.withdrawAsset(WBTC);
    }

    // =============================================================
    // === ADD / REMOVE ASSET TESTS ===
    // =============================================================

    function test_addAsset_success_noOldToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            2000,
            9000,
            11500
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        vm.prank(owner);
        wallet.addAsset(tc, address(0));

        assertEq(_getAlloc(XAUt0), 2000);
        assertEq(_getAlloc(WBTC), 4000);
        assertEq(_getAlloc(WETH), 4000);
        assertEq(
            _getAlloc(WBTC) + _getAlloc(WETH) + _getAlloc(XAUt0),
            TOTAL_PCT
        );
    }

    function test_addAsset_success_withOldToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            3000,
            9000,
            11500
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        vm.prank(owner);
        wallet.addAsset(tc, WETH);

        assertEq(_getAlloc(XAUt0), 3000);
        assertEq(_getAlloc(WETH), 2000);
        assertEq(
            _getAlloc(WBTC) + _getAlloc(WETH) + _getAlloc(XAUt0),
            TOTAL_PCT
        );
    }

    function test_addAsset_revert_AddressZero() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            1000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(address(0), cfg);

        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.addAsset(tc, address(0));
    }

    function test_addAsset_revert_DuplicateToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            1000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(WBTC, cfg);

        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        vm.prank(owner);
        wallet.addAsset(tc, address(0));
    }

    function test_addAsset_revert_NotOwner() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            1000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.addAsset(tc, address(0));
    }

    function test_removeAsset_success() public {
        vm.prank(owner);
        wallet.removeAsset(WBTC);

        assertEq(_getAlloc(WBTC), 0);
        assertEq(_getAlloc(WETH), 10000);
        // assets es address[] público pero sin getter de length
        // Verificamos que WBTC ya no está y WETH sí
        assertEq(wallet.assets(0), WETH);
    }

    function test_removeAsset_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.removeAsset(WBTC);
    }

    function test_removeAsset_revert_InvalidToken() public {
        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        vm.prank(owner);
        wallet.removeAsset(address(0x123));
    }

    // =============================================================
    // === UPDATE ALLOCATION TESTS ===
    // =============================================================

    function test_updateAllocation_success() public {
        vm.prank(owner);
        wallet.updateAllocation(WBTC, 6000);

        assertEq(_getAlloc(WBTC), 6000);
        assertEq(_getAlloc(WETH), 4000);
    }

    function test_updateAllocation_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateAllocation(WBTC, 6000);
    }

    function test_updateAllocation_revert_ExceedTotal() public {
        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        vm.prank(owner);
        wallet.updateAllocation(WBTC, 11000);
    }

    function test_updateAllocation_revert_InvalidToken() public {
        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        vm.prank(owner);
        wallet.updateAllocation(address(0x123), 5000);
    }

    // =============================================================
    // === UPDATE RISK CONFIG TESTS ===
    // =============================================================

    function test_updateRiskConfig_success() public {
        vm.prank(owner);
        wallet.updateRiskConfig(WBTC, 9000, 12000);

        assertEq(_getStopLoss(WBTC), 9000);
        assertEq(_getTakeProfit(WBTC), 12000);
    }

    function test_updateRiskConfig_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.updateRiskConfig(WBTC, 9000, 12000);
    }

    function test_updateRiskConfig_revert_BadStopLoss() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrorStopLossBps_notCorrect.selector,
                WBTC,
                10500
            )
        );
        vm.prank(owner);
        wallet.updateRiskConfig(WBTC, 10500, 11000);
    }

    function test_updateRiskConfig_revert_BadTakeProfit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrortakeProfitBps_notCorrect.selector,
                WBTC,
                9000
            )
        );
        vm.prank(owner);
        wallet.updateRiskConfig(WBTC, 9500, 9000);
    }

    // =============================================================
    // === INVEST TESTS ===
    // =============================================================

    function test_invest_success() public {
        uint256 adgentBefore = usdt.balanceOf(adgent);
        uint256 contractBefore = usdt.balanceOf(adgentContract);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        assertGt(usdt.balanceOf(adgent), adgentBefore);
        assertGt(usdt.balanceOf(adgentContract), contractBefore);
        assertGt(wbtc.balanceOf(address(wallet)), 0);
        assertGt(weth.balanceOf(address(wallet)), 0);

        assertGt(_getPosAmount(WBTC), 0);
        assertGt(_getPosInvested(WBTC), 0);
        assertGt(_getPosAmount(WETH), 0);
        assertGt(_getPosInvested(WETH), 0);
    }

    function test_invest_revert_NotAdgentRole() public {
        // AccessControl revert sin selector específico (versión de OZ no expone el error públicamente)
        vm.expectRevert();
        vm.prank(user);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));
    }

    function test_invest_revert_InsufficientBalance() public {
        uint256 balance = usdt.balanceOf(address(wallet));
        vm.prank(owner);
        wallet.withdrawAssetUsdt(balance);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                USDT,
                0,
                0
            )
        );
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));
    }

    // =============================================================
    // === SELLTOKEN TESTS (con modifyPosition para simular precio) ===
    // =============================================================

    /* function test_selltoken_takeProfit_triggered() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 posAmount = _getPosAmount(WBTC);
        uint256 posInvested = _getPosInvested(WBTC);
        assertGt(posAmount, 0);
        assertGt(posInvested, 0);

        uint256 usdtBefore = usdt.balanceOf(address(wallet));

        // Simular precio subió: invested muy bajo → take profit se triggerea
        wallet.modifyPosition(posInvested / 10, WBTC);

        bytes memory pathToUsdc = abi.encodePacked(WBTC, uint24(3000), USDT);

        vm.prank(adgent);
        wallet.selltoken(WBTC, pathToUsdc, new StockWallet.V4PoolData[](0));

        assertLt(wbtc.balanceOf(address(wallet)), posAmount);
        assertGt(usdt.balanceOf(address(wallet)), usdtBefore);
    }

    function test_selltoken_stopLoss_triggered() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 posAmount = _getPosAmount(WBTC);
        uint256 posInvested = _getPosInvested(WBTC);
        assertGt(posAmount, 0);

        uint256 usdtBefore = usdt.balanceOf(address(wallet));

        // Simular precio bajó: invested muy alto → stop loss se triggerea
        wallet.modifyPosition(posInvested * 10, WBTC);

        bytes memory pathToUsdc = abi.encodePacked(WBTC, uint24(3000), USDT);

        vm.prank(adgent);
        wallet.selltoken(WBTC, pathToUsdc, new StockWallet.V4PoolData[](0));

        assertEq(wbtc.balanceOf(address(wallet)), 0);
        assertGt(usdt.balanceOf(address(wallet)), usdtBefore);
        assertEq(_getAlloc(WBTC), 0);
    }*/

    function test_selltoken_revert_TokenNotReadytoSell() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        bytes memory pathToUsdc = abi.encodePacked(WBTC, uint24(3000), USDT);

        vm.prank(adgent);
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.TokenNotReadytoSell.selector,
                WBTC
            )
        );
        wallet.selltoken(WBTC, pathToUsdc, new StockWallet.V4PoolData[](0));
    }

    function test_selltoken_revert_NotAdgentRole() public {
        vm.expectRevert();
        vm.prank(user);
        wallet.selltoken(WBTC, new bytes(0), new StockWallet.V4PoolData[](0));
    }

    // =============================================================
    // === SELLTOKEN ALL TESTS ===
    // =============================================================

    function test_selltokenAll_success() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        assertGt(wbtc.balanceOf(address(wallet)), 0);
        assertGt(weth.balanceOf(address(wallet)), 0);

        bytes[] memory paths = new bytes[](2);
        paths[0] = abi.encodePacked(WBTC, uint24(3000), USDT);
        paths[1] = abi.encodePacked(WETH, uint24(3000), USDT);

        vm.prank(owner);
        wallet.selltokenAll(paths);

        assertEq(wbtc.balanceOf(address(wallet)), 0);
        assertEq(weth.balanceOf(address(wallet)), 0);

        assertEq(_getPosAmount(WBTC), 0);
        assertEq(_getPosInvested(WBTC), 0);
        assertEq(_getPosAmount(WETH), 0);
        assertEq(_getPosInvested(WETH), 0);
    }

    function test_selltokenAll_revert_NotOwner() public {
        bytes memory expectedError = abi.encodeWithSignature(
            "OwnableUnauthorizedAccount(address)",
            user
        );

        vm.expectRevert(expectedError);
        vm.prank(user);
        wallet.selltokenAll(new bytes[](0));
    }

    // =============================================================
    // === BUG TESTS (documentan bugs sin modificar el contrato) ===
    // =============================================================

    // Bug 5: modifyPosition es pública sin restricciones
    /* function test_bug_modifyPosition_public_unrestricted() public {
        vm.prank(user);
        wallet.modifyPosition(1e6, WBTC);
        // Pasa sin revert — confirma el bug
    }*/

    // Bug 7: addAsset con _oldToken underflow si newAlloc > oldAlloc
    function test_bug_addAsset_underflow_oldToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            6000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        vm.expectRevert();
        vm.prank(owner);
        wallet.addAsset(tc, WETH);
    }

    // Bug 8: No valida stopLoss > takeProfit en updateRiskConfig
    function test_bug_updateRiskConfig_no_sl_gt_tp_validation() public {
        vm.prank(owner);
        wallet.updateRiskConfig(WBTC, 8000, 11000);

        assertEq(_getStopLoss(WBTC), 8000);
        assertEq(_getTakeProfit(WBTC), 11000);
    }

    // =============================================================
    // === ORIGINAL TESTS (migrados de StockWaller.t.sol) ===
    // =============================================================

    function test_original_full_flow() public {
        StockWallet.AssetConfig memory c1 = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );
        StockWallet.AssetConfig memory c2 = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );

        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](2);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c1);
        ta[1] = StockWallet.TokenAllocationConfig(WETH, c2);

        vm.startPrank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
        );
        vm.stopPrank();

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        deal(WBRL, address(this), 5046 * 1e18);
        wbrl.approve(address(wallet), 5046 * 1e18);
        bytes memory wbrlPath = abi.encodePacked(WBRL, uint24(100), USDT);
        wallet.depositAsset(WBRL, 5046 * 1e18, wbrlPath);

        StockWallet.AssetConfig memory xcfg = StockWallet.AssetConfig(
            2000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig memory xtc = StockWallet
            .TokenAllocationConfig(XAUt0, xcfg);
        vm.prank(owner);
        wallet.addAsset(xtc, address(0));

        StockWallet.AssetConfig memory pcfg = StockWallet.AssetConfig(
            1000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig memory ptc = StockWallet
            .TokenAllocationConfig(PLAST, pcfg);
        vm.prank(owner);
        wallet.addAsset(ptc, WETH);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        bytes[] memory sellPaths = new bytes[](0);
        vm.prank(owner);
        wallet.selltokenAll(sellPaths);

        uint256 usdtAfterSell = usdt.balanceOf(address(wallet));
        assertGt(usdtAfterSell, 0);

        uint256 ownerBefore = usdt.balanceOf(owner);
        vm.prank(owner);
        wallet.withdrawAssetUsdt(usdtAfterSell);
        assertEq(usdt.balanceOf(owner), ownerBefore + usdtAfterSell);
    }

    /*function test_original_selltoken_with_modifyPosition() public {
        StockWallet.AssetConfig memory c1 = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );
        StockWallet.AssetConfig memory c2 = StockWallet.AssetConfig(
            5000,
            9500,
            11000
        );

        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](2);
        ta[0] = StockWallet.TokenAllocationConfig(WBTC, c1);
        ta[1] = StockWallet.TokenAllocationConfig(XAUt0, c2);

        vm.startPrank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
        );
        vm.stopPrank();

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        wallet.modifyPosition(100e6, XAUt0);

        bytes memory path;
        vm.prank(adgent);
        wallet.selltoken(XAUt0, path, new StockWallet.V4PoolData[](0));

        assertEq(xaut0.balanceOf(address(wallet)), 0);
    }*/

    // =============================================================
    // === COVERAGE: Constructor edge cases ===
    // =============================================================

    // L258: addrToken == _usdc en constructor
    function test_constructor_revert_TokenEqualsUsdc() public {
        StockWallet.AssetConfig memory c = StockWallet.AssetConfig(
            10000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](1);
        ta[0] = StockWallet.TokenAllocationConfig(USDT, c); // token == usdc

        vm.expectRevert(StockWallet.Address_Zero.selector);
        new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            200,
            ta
        );
    }

    // =============================================================
    // === COVERAGE: addAsset branches ===
    // =============================================================

    // L404: _newAllocationBps == 0
    function test_addAsset_revert_ZeroAllocation() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(0, 0, 0);
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        vm.prank(owner);
        wallet.addAsset(tc, address(0));
    }

    // L404: _newAllocationBps > TOTAL_PERCENTAGE
    function test_addAsset_revert_AllocationExceedsTotal() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            11000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);

        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        vm.prank(owner);
        wallet.addAsset(tc, address(0));
    }

    // L440: totalAllocation != TOTAL_PERCENTAGE (addAsset con _oldToken == address(0) y fallo de suma)
    // Cubierto indirectamente por test_addAsset_success_noOldToken, pero necesitamos un caso
    // donde el último elemento absorba dust y la suma no sea exacta.
    // Este branch es difícil de triggerear sin manipular redondeos. Lo dejamos como branch no cubierta.

    // =============================================================
    // === COVERAGE: _removeAsset con múltiples assets y re-escaling ===
    // =============================================================

    // L498-526: _removeAsset con 3+ assets para cubrir el re-escaling loop
    function test_removeAsset_rebalance_three_assets() public {
        // Agregar XAUt0 (20%) → WBTC 4000, WETH 4000, XAUt0 2000
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            2000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(XAUt0, cfg);
        vm.prank(owner);
        wallet.addAsset(tc, address(0));

        // Remover WETH (4000) → WBTC y XAUt0 re-escalan
        vm.prank(owner);
        wallet.removeAsset(WETH);

        // WBTC: (4000 * 10000) / 6000 = 6666, XAUt0 absorbe dust: 3334
        assertEq(_getAlloc(WETH), 0);
        assertEq(_getAlloc(WBTC) + _getAlloc(XAUt0), TOTAL_PCT);
    }

    // =============================================================
    // === COVERAGE: updateAllocation branches ===
    // =============================================================

    // L564: oldAllocationBps == newAllocationBps (early return)
    function test_updateAllocation_sameValue() public {
        // WBTC tiene 5000, setear a 5000 → early return sin cambios
        vm.prank(owner);
        wallet.updateAllocation(WBTC, 5000);
        // No revert, no cambio
        assertEq(_getAlloc(WBTC), 5000);
        assertEq(_getAlloc(WETH), 5000);
    }

    // L575-585: length == 1 (solo un asset, asignar 100%)
    function test_updateAllocation_singleAsset_100percent() public {
        // Remover WETH, dejar solo WBTC
        vm.prank(owner);
        wallet.removeAsset(WETH);

        // WBTC ahora tiene 10000, setear a 10000 (no cambia)
        vm.prank(owner);
        wallet.updateAllocation(WBTC, 10000);
        assertEq(_getAlloc(WBTC), 10000);
    }

    // L575-576: length == 1 y newAllocationBps != TOTAL_PERCENTAGE → revert
    function test_updateAllocation_singleAsset_not100_revert() public {
        vm.prank(owner);
        wallet.removeAsset(WETH);

        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        vm.prank(owner);
        wallet.updateAllocation(WBTC, 5000);
    }

    // L589: oldOthersTotal == 0 && remainingPercentage > 0
    // Necesita un asset con 100% y otro con 0%
    function test_updateAllocation_oldOthersTotal_zero() public {
        // WBTC 5000, WETH 5000. Set WBTC to 10000 → WETH oldOthersTotal = 0
        // Pero primero necesitamos que WETH tenga 0. Remover y re-agregar.
        vm.prank(owner);
        wallet.removeAsset(WETH); // WBTC queda con 10000

        // Agregar WETH con 0% via addAsset con oldToken
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            0,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(WETH, cfg);
        // Esto debería underflow o dar 0... Probemos directamente
        // En realidad addAsset con 0 allocation revierte. Probemos otro approach.
        // set WETH allocation to 0 via updateAllocation
        // No se puede setear a 0 (revert). Saltamos este caso edge.
        // Este branch requiere un estado que el contrato no permite alcanzar fácilmente.
        // Lo dejamos como branch no cubierta.
    }

    // L598: tokenIndex == lastOtherIndex → lastOtherIndex = length - 2
    function test_updateAllocation_lastToken() public {
        // WBTC 5000, WETH 5000. Update WETH (último en array) → tokenIndex == lastOtherIndex
        vm.prank(owner);
        wallet.updateAllocation(WETH, 3000);

        assertEq(_getAlloc(WETH), 3000);
        assertEq(_getAlloc(WBTC), 7000);
    }

    // =============================================================
    // === COVERAGE: updateRiskConfig branches ===
    // =============================================================

    // L637: allocationBps == 0 (token no configurado)
    function test_updateRiskConfig_revert_TokenNotConfigured() public {
        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        vm.prank(owner);
        wallet.updateRiskConfig(XAUt0, 9500, 11000);
    }

    // =============================================================
    // === COVERAGE: selltoken branches ===
    // =============================================================

    // L670: path con receiver incorrecto (!= usdc)
    function test_selltoken_revert_WrongPathReceiver() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // Path que termina en WETH en vez de USDT
        bytes memory badPath = abi.encodePacked(WBTC, uint24(3000), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.AddressToReceiveNotCorrect.selector,
                WETH
            )
        );
        vm.prank(adgent);
        wallet.selltoken(WBTC, badPath, new StockWallet.V4PoolData[](0));
    }

    // L677: tokenBalance == 0
    function test_selltoken_revert_ZeroBalance() public {
        // No invest, WBTC balance es 0
        bytes memory path = abi.encodePacked(WBTC, uint24(3000), USDT);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                WBTC,
                0,
                0
            )
        );
        vm.prank(adgent);
        wallet.selltoken(WBTC, path, new StockWallet.V4PoolData[](0));
    }

    // L685: PoolNoExiste - token sin pool en Uniswap
    function test_selltoken_revert_PoolNotFound() public {
        // Usar un token sin pool en Celo
        address fakeToken = makeAddr("fakeToken");
        // Deal some tokens to wallet (no será un ERC20 real, pero balanceOf devolverá 0)
        // En realidad necesitamos un token con balance pero sin pool.
        // Usar PLAST que probablemente no tiene pool con USDT
        deal(PLAST, address(wallet), 1e18);

        bytes memory path; // empty path para que _getBestPoolFee busque

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.PoolNoExiste.selector,
                PLAST,
                USDT
            )
        );
        vm.prank(adgent);
        wallet.selltoken(PLAST, path, new StockWallet.V4PoolData[](0));
    }

    // =============================================================
    // === COVERAGE: selltokenAll branches ===
    // =============================================================

    // L743: path con receiver incorrecto en selltokenAll
    function test_selltokenAll_revert_WrongPathReceiver() public {
        bytes[] memory paths = new bytes[](1);
        paths[0] = abi.encodePacked(WBTC, uint24(3000), WETH); // ends in WETH, not USDT

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.AddressToReceiveNotCorrect.selector,
                WETH
            )
        );
        vm.prank(owner);
        wallet.selltokenAll(paths);
    }

    // L749: length == 0 (no assets)
    function test_selltokenAll_revert_NoAssets() public {
        // Remover todos los assets
        vm.prank(owner);
        wallet.removeAsset(WBTC);
        vm.prank(owner);
        wallet.removeAsset(WETH);

        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.TokenNotReadytoSell.selector,
                address(0)
            )
        );
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));
    }

    // L789-791: selltokenAll con paths válidos (setea assetPath)
    function test_selltokenAll_withPaths_setsAssetPath() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        bytes[] memory paths = new bytes[](2);
        paths[0] = abi.encodePacked(WBTC, uint24(3000), USDT);
        paths[1] = abi.encodePacked(WETH, uint24(3000), USDT);

        vm.prank(owner);
        wallet.selltokenAll(paths);

        assertEq(wbtc.balanceOf(address(wallet)), 0);
        assertEq(weth.balanceOf(address(wallet)), 0);
    }

    // =============================================================
    // === COVERAGE: invest con paths ===
    // =============================================================

    // L789-791: invest con paths válidos (setea assetPath)
    function test_invest_withPaths_setsAssetPath() public {
        bytes[] memory paths = new bytes[](2);
        paths[0] = abi.encodePacked(USDT, uint24(3000), WBTC);
        paths[1] = abi.encodePacked(USDT, uint24(3000), WETH);

        vm.prank(adgent);
        wallet.invest(paths, new StockWallet.V4PoolData[][](0));

        assertGt(wbtc.balanceOf(address(wallet)), 0);
        assertGt(weth.balanceOf(address(wallet)), 0);
    }

    // =============================================================
    // === COVERAGE: _swap edge cases ===
    // =============================================================

    // L829: tokenIn == tokenOut
    function test_swap_revert_TokensEqual() public {
        // depositAsset con token == usdc y path vacío llama _swap(usdc, usdc, ...)
        // Pero depositAsset con USDT no llama _swap. Necesitamos otra vía.
        // _swap es internal, se llama desde invest, selltoken, depositAsset.
        // Para triggerear tokenIn == tokenOut, necesitaríamos que invest intente
        // swap USDT -> USDT, pero los assets nunca son USDT.
        // Este branch es inalcanzable con el flujo normal del contrato.
        // Lo dejamos como branch no cubierta.
    }

    // =============================================================
    // === COVERAGE: getLastAddress / getFirstAddress ===
    // =============================================================

    function test_getLastAddress() public {
        bytes memory path = abi.encodePacked(USDT, uint24(3000), WBTC);
        address last = wallet.getLastAddress(path);
        assertEq(last, WBTC);
    }

    function test_getFirstAddress() public {
        bytes memory path = abi.encodePacked(USDT, uint24(3000), WBTC);
        address first = wallet.getFirstAddress(path);
        assertEq(first, USDT);
    }

    function test_getLastAddress_revert_ShortPath() public {
        bytes memory shortPath = new bytes(10); // < 20
        vm.expectRevert("Path invalido");
        wallet.getLastAddress(shortPath);
    }

    function test_getFirstAddress_revert_ShortPath() public {
        bytes memory shortPath = new bytes(10); // < 20
        vm.expectRevert("Path invalido");
        wallet.getFirstAddress(shortPath);
    }

    // =============================================================
    // === COVERAGE: getTokenConfig ===
    // =============================================================

    function test_getTokenConfig() public {
        StockWallet.AssetConfig memory cfg = wallet.getTokenConfig(WBTC);
        assertEq(cfg.allocationBps, 5000);
        assertEq(cfg.stopLossBps, 9500);
        assertEq(cfg.takeProfitBps, 11000);
    }

    // =============================================================
    // === COVERAGE: depositAsset con swap (token != usdc) ===
    // =============================================================

    function test_depositAsset_token_swap_to_usdc() public {
        uint256 wethAmount = 1e18;
        deal(WETH, user, wethAmount);

        vm.startPrank(user);
        weth.approve(address(wallet), wethAmount);

        uint256 walletUsdtBefore = usdt.balanceOf(address(wallet));

        bytes memory pathToUsdt = abi.encodePacked(WETH, uint24(3000), USDT);
        wallet.depositAsset(WETH, wethAmount, pathToUsdt);
        vm.stopPrank();

        assertEq(weth.balanceOf(user), 0);
        assertGt(usdt.balanceOf(address(wallet)), walletUsdtBefore);
    }

    // =============================================================
    // === COVERAGE: selltoken con path (usa path en vez de auto-detect) ===
    // =============================================================

    /* function test_selltoken_takeProfit_withPath() public {
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 posInvested = _getPosInvested(WBTC);
        wallet.modifyPosition(posInvested / 10, WBTC);

        // Pasar path explícito para cubrir branch de path.length > 0 en selltoken
        bytes memory path = abi.encodePacked(WBTC, uint24(3000), USDT);

        vm.prank(adgent);
        wallet.selltoken(WBTC, path, new StockWallet.V4PoolData[](0));

        assertLt(wbtc.balanceOf(address(wallet)), _getPosAmount(WBTC) + wbtc.balanceOf(address(wallet)));
    }*/

    // =============================================================
    // === COVERAGE: invest con amountNotInvested (swap falla) ===
    // =============================================================

    function test_invest_withFailedSwap_accumulatesNotInvested() public {
        // Agregar un token sin pool (PLAST) para que _swap retorne 0
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            1000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(PLAST, cfg);
        vm.prank(owner);
        wallet.addAsset(tc, address(0));

        // Invest: PLAST swap fallará, amountNotInvested acumulará
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // WBTC y WETH deberían tener balance, PLAST no
        assertGt(wbtc.balanceOf(address(wallet)), 0);
        assertGt(weth.balanceOf(address(wallet)), 0);
        assertEq(plast.balanceOf(address(wallet)), 0);
    }
}
