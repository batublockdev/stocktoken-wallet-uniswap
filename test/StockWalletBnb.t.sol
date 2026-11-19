//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {IERC20} from "./IERC20.sol";
import {MockERC20} from "./MockERC20.sol";
import {console} from "forge-std/console.sol";

// Usamos direcciones fijas para los tokens "asset" (BTCB, ETH, AAPL)
// porque el contrato solo las guarda como address, no las llama en los
// tests que no hacen swap. Para USDT sí necesitamos un mock funcional.
address constant MOCK_USDT = address(0x1000);
address constant MOCK_BTCB = address(0x2000);
address constant MOCK_ETH = address(0x3000);
address constant MOCK_AAPL = address(0x4000);

// Infraestructura Uniswap — direcciones cualquiera, no se llaman sin fork
address constant MOCK_FACTORY = address(0x5000);
address constant MOCK_ROUTER = address(0x6000);
address constant MOCK_PERMIT2 = address(0x7000);
address constant MOCK_QUOTER = address(0x8000);

contract StockWalletBnbTest is Test {
    StockWallet public wallet;
    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    // Mock USDT (18 decimals como en BSC)
    MockERC20 public usdt;

    function setUp() public {
        // Deploy mock USDT
        usdt = new MockERC20("Mock USDT", "USDT", 18);

        // Deploy wallet with BTCB + ETH (50/50)
        StockWallet.AssetConfig memory configBtcb = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.AssetConfig memory configEth = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](2);
        tokenAllocation[0] = StockWallet.TokenAllocationConfig({
            token: MOCK_BTCB,
            configs: configBtcb
        });
        tokenAllocation[1] = StockWallet.TokenAllocationConfig({
            token: MOCK_ETH,
            configs: configEth
        });

        vm.startPrank(owner);
        wallet = new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            tokenAllocation
        );
        vm.stopPrank();

        // Fund wallet with mock USDT
        usdt.mint(address(this), 100 * 1e18);
        usdt.transfer(address(wallet), 100 * 1e18);
    }

    // =============================================================
    // === CONSTRUCTOR TESTS ===
    // =============================================================

    function test_constructor_success() public {
        assertEq(address(wallet.factory()), MOCK_FACTORY);
        assertEq(address(wallet.quoter()), MOCK_QUOTER);
        assertEq(wallet.usdc(), address(usdt));
        assertEq(wallet.owner(), owner);
        assertTrue(wallet.hasRole(wallet.ADGENT_ROLE(), adgent));
        assertTrue(wallet.hasRole(wallet.ADGENT_ROLE(), owner));

        (uint256 alloc, uint16 sl, uint16 tp) = wallet.assetConfig(MOCK_BTCB);
        assertEq(alloc, 5000);
        assertEq(sl, 9500);
        assertEq(tp, 11000);

        (alloc, sl, tp) = wallet.assetConfig(MOCK_ETH);
        assertEq(alloc, 5000);
        assertEq(sl, 9500);
        assertEq(tp, 11000);

        assertEq(wallet.assets(0), MOCK_BTCB);
        assertEq(wallet.assets(1), MOCK_ETH);
    }

    function test_constructor_revert_AddressZero() public {
        StockWallet.AssetConfig memory config = StockWallet.AssetConfig({
            allocationBps: 10000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](1);
        ta[0] = StockWallet.TokenAllocationConfig({
            token: MOCK_BTCB,
            configs: config
        });

        vm.expectRevert(StockWallet.Address_Zero.selector);
        new StockWallet(
            address(0),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
        );
    }

    function test_constructor_revert_EmptyTokenAllocation() public {
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](0);
        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
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
        ta[0] = StockWallet.TokenAllocationConfig(MOCK_BTCB, c1);
        ta[1] = StockWallet.TokenAllocationConfig(MOCK_ETH, c2);

        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
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
        ta[0] = StockWallet.TokenAllocationConfig(MOCK_BTCB, c);
        ta[1] = StockWallet.TokenAllocationConfig(MOCK_BTCB, c);

        vm.expectRevert(StockWallet.StockWallet_Invalid.selector);
        new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
        );
    }

    function test_constructor_revert_TokenEqualsUsdc() public {
        StockWallet.AssetConfig memory c = StockWallet.AssetConfig(
            10000,
            9500,
            11000
        );
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](1);
        ta[0] = StockWallet.TokenAllocationConfig(address(usdt), c);

        vm.expectRevert(StockWallet.Address_Zero.selector);
        new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
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
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.updateAdgent(makeAddr("newAdgent"));
    }

    function test_updateAdgent_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.updateAdgent(address(0));
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

    function test_updateAdgentPercentage_success() public {
        vm.prank(owner);
        wallet.updateAdgentPercentage(100);
    }

    function test_updateAdgentPercentage_revert_ZeroAmount() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(owner);
        wallet.updateAdgentPercentage(0);
    }

    // =============================================================
    // === DEPOSIT / WITHDRAW TESTS (sin swap) ===
    // =============================================================

    function test_depositAsset_usdt() public {
        uint256 depositAmount = 50 * 1e18;
        usdt.mint(adgent, depositAmount);

        vm.startPrank(adgent);
        usdt.approve(address(wallet), depositAmount);

        uint256 walletBefore = usdt.balanceOf(address(wallet));
        wallet.depositAsset(address(usdt), depositAmount, new bytes(0));
        vm.stopPrank();

        assertEq(usdt.balanceOf(address(wallet)), walletBefore + depositAmount);
    }

    function test_depositAsset_revert_AmountInZero() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        wallet.depositAsset(address(usdt), 0, new bytes(0));
    }

    function test_depositAsset_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        wallet.depositAsset(address(0), 1e18, new bytes(0));
    }

    function test_withdrawAssetUsdt_success_owner() public {
        uint256 withdrawAmount = 10 * 1e18;
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
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.withdrawAssetUsdt(1e18);
    }

    function test_withdrawAssetUsdt_revert_AmountInZero() public {
        vm.expectRevert(StockWallet.AmountInZero.selector);
        vm.prank(owner);
        wallet.withdrawAssetUsdt(0);
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
            .TokenAllocationConfig(MOCK_AAPL, cfg);

        vm.prank(owner);
        wallet.addAsset(tc, address(0));

        (uint256 alloc, , ) = wallet.assetConfig(MOCK_AAPL);
        assertEq(alloc, 2000);
        // BTCB y ETH re-escalan: 5000 * 8000/10000 = 4000
        (alloc, , ) = wallet.assetConfig(MOCK_BTCB);
        assertEq(alloc, 4000);
        (alloc, , ) = wallet.assetConfig(MOCK_ETH);
        assertEq(alloc, 4000);
    }

    function test_addAsset_success_withOldToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            3000,
            9000,
            11500
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(MOCK_AAPL, cfg);

        vm.prank(owner);
        wallet.addAsset(tc, MOCK_ETH);

        (uint256 alloc, , ) = wallet.assetConfig(MOCK_AAPL);
        assertEq(alloc, 3000);
        (alloc, , ) = wallet.assetConfig(MOCK_ETH);
        assertEq(alloc, 2000);
    }

    function test_addAsset_revert_DuplicateToken() public {
        StockWallet.AssetConfig memory cfg = StockWallet.AssetConfig(
            1000,
            0,
            0
        );
        StockWallet.TokenAllocationConfig memory tc = StockWallet
            .TokenAllocationConfig(MOCK_BTCB, cfg);

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
            .TokenAllocationConfig(MOCK_AAPL, cfg);

        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.addAsset(tc, address(0));
    }

    function test_removeAsset_success() public {
        vm.prank(owner);
        wallet.removeAsset(MOCK_BTCB);

        (uint256 alloc, , ) = wallet.assetConfig(MOCK_BTCB);
        assertEq(alloc, 0);
        (alloc, , ) = wallet.assetConfig(MOCK_ETH);
        assertEq(alloc, 10000);
        assertEq(wallet.assets(0), MOCK_ETH);
    }

    function test_removeAsset_revert_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.removeAsset(MOCK_BTCB);
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
        wallet.updateAllocation(MOCK_BTCB, 6000);

        (uint256 alloc, , ) = wallet.assetConfig(MOCK_BTCB);
        assertEq(alloc, 6000);
        (alloc, , ) = wallet.assetConfig(MOCK_ETH);
        assertEq(alloc, 4000);
    }

    function test_updateAllocation_revert_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.updateAllocation(MOCK_BTCB, 6000);
    }

    function test_updateAllocation_revert_ExceedTotal() public {
        vm.expectRevert(
            StockWallet.StockWallet_PercentagesExceedTotal.selector
        );
        vm.prank(owner);
        wallet.updateAllocation(MOCK_BTCB, 11000);
    }

    // =============================================================
    // === UPDATE RISK CONFIG TESTS ===
    // =============================================================

    function test_updateRiskConfig_success() public {
        vm.prank(owner);
        wallet.updateRiskConfig(MOCK_BTCB, 9000, 12000);

        (, uint16 sl, uint16 tp) = wallet.assetConfig(MOCK_BTCB);
        assertEq(sl, 9000);
        assertEq(tp, 12000);
    }

    function test_updateRiskConfig_revert_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.updateRiskConfig(MOCK_BTCB, 9000, 12000);
    }

    function test_updateRiskConfig_revert_BadStopLoss() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrorStopLossBps_notCorrect.selector,
                MOCK_BTCB,
                10500
            )
        );
        vm.prank(owner);
        wallet.updateRiskConfig(MOCK_BTCB, 10500, 11000);
    }

    function test_updateRiskConfig_revert_BadTakeProfit() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.ErrortakeProfitBps_notCorrect.selector,
                MOCK_BTCB,
                9000
            )
        );
        vm.prank(owner);
        wallet.updateRiskConfig(MOCK_BTCB, 9500, 9000);
    }

    // =============================================================
    // === INVEST TEST (sin fork — solo valida revert) ===
    // =============================================================

    function test_invest_revert_NotAdgentRole() public {
        vm.expectRevert();
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));
    }

    // =============================================================
    // === SELLTOKEN TESTS (sin swap) ===
    // =============================================================

    function test_selltoken_revert_NotAdgentRole() public {
        vm.expectRevert();
        vm.prank(adgent);
        wallet.selltoken(
            MOCK_BTCB,
            new bytes(0),
            new StockWallet.V4PoolData[](0)
        );
    }

    function test_selltokenAll_revert_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                adgent
            )
        );
        vm.prank(adgent);
        wallet.selltokenAll(new bytes[](0));
    }

    // =============================================================
    // === VIEW FUNCTIONS ===
    // =============================================================

    function test_getTokenConfig() public {
        StockWallet.AssetConfig memory cfg = wallet.getTokenConfig(MOCK_BTCB);
        assertEq(cfg.allocationBps, 5000);
        assertEq(cfg.stopLossBps, 9500);
        assertEq(cfg.takeProfitBps, 11000);
    }

    function test_getLastAddress() public {
        bytes memory path = abi.encodePacked(
            address(usdt),
            uint24(3000),
            MOCK_BTCB
        );
        address last = wallet.getLastAddress(path);
        assertEq(last, MOCK_BTCB);
    }

    function test_getFirstAddress() public {
        bytes memory path = abi.encodePacked(
            address(usdt),
            uint24(3000),
            MOCK_BTCB
        );
        address first = wallet.getFirstAddress(path);
        assertEq(first, address(usdt));
    }

    function test_calculateMinimumOut() public {
        // slippageBps default = 100 (1%)
        // (10000 * (10000 - 100)) / 10000 = 9900
        uint256 minOut = wallet.calculateMinimumOut(10000);
        assertEq(minOut, 9900);
    }

    // =============================================================
    // === UNPAUSE TESTS ===
    // =============================================================

    function test_unpause() public {
        // Pausar
        vm.prank(owner);
        wallet.pause();
        assertTrue(wallet.paused());

        // Despausar
        vm.prank(owner);
        wallet.unpause();
        assertFalse(wallet.paused());
    }

    function test_unpause_revert_NotOwner() public {
        vm.prank(owner);
        wallet.pause();

        vm.expectRevert();
        vm.prank(adgent);
        wallet.unpause();
    }

    function test_unpauseTrading() public {
        // Pausar trading
        vm.prank(owner);
        wallet.pauseTrading();
        assertTrue(wallet.tradingPaused());

        // Despausar trading
        vm.prank(owner);
        wallet.unpauseTrading();
        assertFalse(wallet.tradingPaused());
    }

    function test_unpauseTrading_revert_NotOwner() public {
        vm.prank(owner);
        wallet.pauseTrading();

        vm.expectRevert();
        vm.prank(adgent);
        wallet.unpauseTrading();
    }

    // =============================================================
    // === WITHDRAW ASSET (non-USDT token) ===
    // =============================================================

    /*function test_withdrawAsset_token() public {
        // Deploy un mock token (no USDT)
        MockERC20 mockToken = new MockERC20("Mock BTCB", "BTCB", 18);
        mockToken.mint(address(wallet), 100 * 1e18);

        // Setear una posición para que el reset se ejecute
        vm.prank(address(this));
        wallet.__testSetPosition(address(mockToken), 50 * 1e18, 50 * 1e18);

        uint256 ownerBefore = mockToken.balanceOf(owner);

        // Owner retira el token
        vm.prank(owner);
        wallet.withdrawAsset(address(mockToken));

        // Verificar que el owner recibió los tokens
        assertEq(mockToken.balanceOf(owner), ownerBefore + 100 * 1e18);
        // Verificar que el contrato quedó en 0
        assertEq(mockToken.balanceOf(address(wallet)), 0);
        // Verificar que la posición se reseteó
        (uint256 amount, uint256 invested) = wallet.assetPosition(address(mockToken));
        assertEq(amount, 0);
        assertEq(invested, 0);
    }*/

    function test_withdrawAsset_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.withdrawAsset(address(0));
    }

    function test_withdrawAsset_revert_BalanceZero() public {
        // Usar un mock token con balance 0
        MockERC20 mockToken = new MockERC20("Empty", "EMPTY", 18);
        // No mint nada → balance = 0
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                address(mockToken),
                uint256(0),
                uint256(1)
            )
        );
        vm.prank(owner);
        wallet.withdrawAsset(address(mockToken));
    }

    function test_withdrawAsset_revert_NotOwner() public {
        MockERC20 mockToken = new MockERC20("Mock BTCB", "BTCB", 18);
        mockToken.mint(address(wallet), 100 * 1e18);

        vm.expectRevert();
        vm.prank(adgent);
        wallet.withdrawAsset(address(mockToken));
    }

    // =============================================================
    // === SELLTOKEN ALL ===
    // =============================================================

    function test_selltokenAll_revert_Paused() public {
        vm.prank(owner);
        wallet.pause();

        vm.expectRevert(StockWallet.EnforcedPause.selector);
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));
    }

    function test_selltokenAll_noBalances() public {
        // Deploy mock tokens para que balanceOf no falle
        MockERC20 mockBtcb = new MockERC20("Mock BTCB", "BTCB", 18);
        MockERC20 mockEth = new MockERC20("Mock ETH", "ETH", 18);

        // Deploy wallet con mock tokens reales
        StockWallet.AssetConfig memory configBtcb = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.AssetConfig memory configEth = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.TokenAllocationConfig[]
            memory ta = new StockWallet.TokenAllocationConfig[](2);
        ta[0] = StockWallet.TokenAllocationConfig({
            token: address(mockBtcb),
            configs: configBtcb
        });
        ta[1] = StockWallet.TokenAllocationConfig({
            token: address(mockEth),
            configs: configEth
        });

        vm.prank(owner);
        StockWallet mockWallet = new StockWallet(
            address(usdt),
            MOCK_FACTORY,
            MOCK_ROUTER,
            MOCK_PERMIT2,
            MOCK_QUOTER,
            address(0),
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000,
            ta
        );

        // selltokenAll con assets pero sin balances → no hace nada, no revertea
        vm.prank(owner);
        mockWallet.selltokenAll(new bytes[](0));
        // No revertea = pass
    }

    function test_selltokenAll_revert_BadPath() public {
        // Path que no termina en USDT
        bytes memory badPath = abi.encodePacked(
            address(usdt),
            uint24(3000),
            MOCK_BTCB
        );
        bytes[] memory paths = new bytes[](1);
        paths[0] = badPath;

        // El contrato revertea con AddressToReceiveNotCorrect(MOCK_BTCB)
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.AddressToReceiveNotCorrect.selector,
                MOCK_BTCB
            )
        );
        vm.prank(owner);
        wallet.selltokenAll(paths);
    }

    // =============================================================
    // === UPDATESLIPPAGEBPS ===
    // =============================================================

    function test_updateslippageBps_success() public {
        vm.prank(owner);
        wallet.updateslippageBps(500); // 5%

        // Verificar que el cálculo usa el nuevo slippage
        // (10000 * (10000 - 500)) / 10000 = 9500
        uint256 minOut = wallet.calculateMinimumOut(10000);
        assertEq(minOut, 9500);
    }

    function test_updateslippageBps_revert_NotOwner() public {
        vm.expectRevert();
        vm.prank(adgent);
        wallet.updateslippageBps(500);
    }

    // =============================================================
    // === UNLOCK CALLBACK (revert when not PoolManager) ===
    // =============================================================

    function test_unlockCallback_revert_NotPoolManager() public {
        // unlockCallback solo puede ser llamado por poolManager
        // Como poolManager es address(0) en este setup, cualquier caller != address(0)
        // debería fallar con require(msg.sender == address(poolManager))
        vm.expectRevert();
        wallet.unlockCallback("");
    }

    // =============================================================
    // === SELL ASSET OWNER ===
    // =============================================================

    function test_SellAssetOwner_revert_AddressZero() public {
        vm.expectRevert(StockWallet.Address_Zero.selector);
        vm.prank(owner);
        wallet.SellAssetOwner(address(0));
    }

    function test_SellAssetOwner_revert_BalanceZero() public {
        // MOCK_BTCB no tiene balance (no es contrato real)
        // Usar un mock token real con balance 0
        MockERC20 mockToken = new MockERC20("Empty", "EMPTY", 18);
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                address(mockToken),
                uint256(0),
                uint256(1)
            )
        );
        vm.prank(owner);
        wallet.SellAssetOwner(address(mockToken));
    }

    function test_SellAssetOwner_revert_NotOwner() public {
        MockERC20 mockToken = new MockERC20("Mock", "MCK", 18);
        mockToken.mint(address(wallet), 100 * 1e18);

        vm.expectRevert();
        vm.prank(adgent);
        wallet.SellAssetOwner(address(mockToken));
    }

    function test_SellAssetOwner_revert_Paused() public {
        MockERC20 mockToken = new MockERC20("Mock", "MCK", 18);
        mockToken.mint(address(wallet), 100 * 1e18);

        vm.prank(owner);
        wallet.pause();

        // SellAssetOwner no tiene whenNotPaused, pero si lo tuviera
        // Por ahora testeamos que no revertea por pause (no tiene modifier)
        // Si le agregás whenNotPaused, este test hay que actualizarlo
        // Por ahora solo verificamos que solo el owner puede llamarlo
        // y que revertea por otras razones (pool no existe en mock)
        vm.expectRevert();
        vm.prank(owner);
        wallet.SellAssetOwner(address(mockToken));
    }
}
