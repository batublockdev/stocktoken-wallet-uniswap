// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {IERC20} from "./IERC20.sol";
import {IPoolScanner} from "../src/IPoolScanner.sol";
import {UniswapV4PoolScanner} from "../src/UniswapV4PoolScanner.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {
    GOOGLE,
    ETH,
    USDT,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNISWAP_V4_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2
} from "./ConstantsBnb.sol";

/**
 * @title TestSellToken
 * @notice Tests de selltoken() con triggers de stop-loss y take-profit.
 *
 *         Usa __testSetPosition() para simular movimientos de precio sin
 *         depender de cambios reales del mercado. Esto permite testear:
 *         1. Stop-loss: el precio del token cae por debajo del umbral → vende todo
 *         2. Take-profit: el precio del token sube por encima del umbral → vende solo la ganancia
 *         3. No trigger: el precio está en rango → revertea con TokenNotReadytoSell
 *
 *         Requiere fork de BSC mainnet en bloque >= 133660000 (V4 PoolManager)
 *
 *         ⚠️ NOTA: __testSetPosition es una función TEST ONLY que debe eliminarse
 *            antes de deployar en mainnet.
 */
contract TestSellToken is Test {
    StockWallet public wallet;
    UniswapV4PoolScanner public scanner;

    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    // --- V4 Infrastructure on BSC ---
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;
    address constant UNIVERSAL_ROUTER_V4 =
        0x1906c1d672b88cD1B9aC7593301cA990F94Eae07;

    // Scanner ya deployado en BSC (block 134522506)
    address constant V4_SCANNER = 0xB442ce9A9f3480a7Cad578296917649d9a451cc7;

    // --- Tokens ---
    IERC20 private usdt = IERC20(USDT);
    IERC20 private google = IERC20(GOOGLE);
    IERC20 private eth = IERC20(ETH);

    // Fork block - must be >= 133660000 for V4 PoolManager
    uint256 constant FORK_BLOCK = 133660000;

    // =============================================================
    // === SETUP ===
    // =============================================================

    function setUp() public {
        vm.createSelectFork(
            "https://bnb-mainnet.g.alchemy.com/v2/alch_3YuxgQWBEEmRG1qX352X6",
            FORK_BLOCK
        );
        scanner = UniswapV4PoolScanner(V4_SCANNER);
    }

    /**
     * @dev Deploya una wallet con 2 tokens (GOOGLE 50%, ETH 50%).
     *      Stop-loss = 9000 bps (90% del investido → 10% de pérdida máxima)
     *      Take-profit = 12000 bps (120% del investido → 20% de ganancia)
     */
    function _deployWallet() internal returns (StockWallet) {
        address[] memory tokens = new address[](2);
        tokens[0] = GOOGLE;
        tokens[1] = ETH;

        StockWallet.AssetConfig[]
            memory configs = new StockWallet.AssetConfig[](2);
        // GOOGLE: 50% allocation, SL=9000 (10% loss), TP=12000 (20% gain)
        configs[0] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });
        // ETH: 50% allocation, SL=9000 (10% loss), TP=12000 (20% gain)
        configs[1] = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9000,
            takeProfitBps: 12000
        });

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](
                tokens.length
            );
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAllocation[i] = StockWallet.TokenAllocationConfig({
                token: tokens[i],
                configs: configs[i]
            });
        }

        vm.prank(owner);
        return
            new StockWallet(
                USDT,
                UNISWAP_V3_FACTORY,
                UNIVERSAL_ROUTER_V4,
                PERMIT2,
                UNISWAP_V3_QUOTER,
                UNISWAP_V4_QUOTER,
                POOL_MANAGER,
                address(scanner),
                adgent,
                adgentContract,
                2000, // 20% adgent fee
                tokenAllocation
            );
    }

    /**
     * @dev Fondea la wallet con USDT para invest.
     */
    function _fundWallet(uint256 amount) internal {
        deal(USDT, address(this), amount);
        usdt.transfer(address(wallet), amount);
    }

    /**
     * @dev Helper: construye V4PoolData para pasar a invest/selltoken.
     */
    function _makeV4Pool(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        int24 tickSpacing
    ) internal pure returns (StockWallet.V4PoolData memory) {
        return
            StockWallet.V4PoolData({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: address(0)
            });
    }

    // =============================================================
    // === TEST 1: STOP-LOSS — el precio cae, vende todo ===
    // =============================================================

    /**
     * @notice Test stop-loss: simula que el precio de GOOGLE cayó 15%
     *         (por debajo del stop-loss de 10%) y verifica que selltoken()
     *         vende todos los tokens y remueve el asset del portfolio.
     *
     *         Flujo:
     *         1. Deploy + fund con 1000 USDT
     *         2. invest() — compra GOOGLE y ETH
     *         3. __testSetPosition() — simula que el invested era más alto
     *            (como si el precio hubiera caído, el valor actual es menor)
     *         4. selltoken(GOOGLE) — debería trigger stop-loss
     *         5. Verificar: GOOGLE balance = 0, GOOGLE removido del portfolio
     */
    /* function test_selltoken_stopLoss() public {
        console.log("=== TEST: selltoken STOP-LOSS ===");

        wallet = _deployWallet();
        _fundWallet(1000 * 1e18);

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 googleBalance = google.balanceOf(address(wallet));
        uint256 ethBalance = eth.balanceOf(address(wallet));
        console.log("Despues de invest:");
        console.log("  GOOGLE balance:", googleBalance);
        console.log("  ETH balance:", ethBalance);

        // Leer la posición real después de invest
        (uint256 posAmount, uint256 posInvested) = wallet.assetPosition(GOOGLE);
        console.log("  GOOGLE position amount:", posAmount);
        console.log("  GOOGLE position invested:", posInvested);

        // --- SIMULAR STOP-LOSS ---
        // El stop-loss es 9000 bps = 90% del invested.
        // minimumToLose = posInvested * 9000 / 10000
        // Si el precio actual del token cae a 85% del invested → trigger SL
        //
        // Para simular: seteamos invested un 18% más alto que el amount real
        // Esto hace que tokenPriceUsdcNow (que usa el amount actual) sea ~85%
        // del invested → por debajo del 90% del stop-loss
        //
        // __testSetPosition(token, amount, invested_inflado)
        uint256 inflatedInvested = (posInvested * 11800) / 10000; // +18%
        vm.prank(address(this)); // cualquier caller puede usar __testSetPosition
        wallet.__testSetPosition(GOOGLE, posAmount, inflatedInvested);

        (, uint256 newInvested) = wallet.assetPosition(GOOGLE);
        console.log("Despues de __testSetPosition:");
        console.log("  GOOGLE invested (inflado):", newInvested);

        // --- SELLTOKEN (debería trigger stop-loss) ---
        uint256 usdtBefore = usdt.balanceOf(address(wallet));

        vm.prank(adgent);
        wallet.selltoken(GOOGLE, "", new StockWallet.V4PoolData[](0));

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        uint256 googleAfter = google.balanceOf(address(wallet));

        console.log("Despues de selltoken (stop-loss):");
        console.log("  USDT recibido:", usdtAfter - usdtBefore);
        console.log("  GOOGLE restante:", googleAfter);

        // Verificar: vendió todo (stop-loss vende todo)
        assertEq(googleAfter, 0, "Stop-loss should sell ALL tokens");

        // Verificar: recibió USDT
        assertGt(usdtAfter - usdtBefore, 0, "Should receive USDT from stop-loss");

        console.log("=== STOP-LOSS OK ===");
    }*/

    // =============================================================
    // === TEST 2: TAKE-PROFIT — el precio sube, vende solo la ganancia ===
    // =============================================================

    /**
     * @notice Test take-profit: simula que el precio de GOOGLE subió 25%
     *         (por encima del take-profit de 20%) y verifica que selltoken()
     *         vende solo la ganancia (diferencia entre balance actual y
     *         equivalente a la inversión original al precio actual).
     *
     *         Flujo:
     *         1. Deploy + fund con 1000 USDT
     *         2. invest() — compra GOOGLE y ETH
     *         3. __testSetPosition() — simula que el invested es más bajo
     *            (como si el precio hubiera subido, el balance actual vale más)
     *         4. selltoken(GOOGLE) — debería trigger take-profit
     *         5. Verificar: GOOGLE balance > 0 (solo vendió la ganancia)
     */
    /*function test_selltoken_takeProfit() public {
        console.log("=== TEST: selltoken TAKE-PROFIT ===");

        wallet = _deployWallet();
        _fundWallet(1000 * 1e18);

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 googleBalance = google.balanceOf(address(wallet));
        (uint256 posAmount, uint256 posInvested) = wallet.assetPosition(GOOGLE);

        console.log("Despues de invest:");
        console.log("  GOOGLE balance:", googleBalance);
        console.log("  GOOGLE position amount:", posAmount);
        console.log("  GOOGLE position invested:", posInvested);

        // --- SIMULAR TAKE-PROFIT ---
        // El take-profit es 12000 bps = 120% del invested.
        // minimumToWin = posInvested * 12000 / 10000
        // Si el precio actual del token sube a 125% del invested → trigger TP
        //
        // Para simular: seteamos invested un 20% más bajo que el amount real
        // Esto hace que tokenPriceUsdcNow sea ~125% del invested
        // → por encima del 120% del take-profit
        //
        // __testSetPosition(token, amount, invested_deflado)
        uint256 deflatedInvested = (posInvested * 8000) / 10000; // -20%
        vm.prank(address(this));
        wallet.__testSetPosition(GOOGLE, posAmount, deflatedInvested);

        (, uint256 newInvested) = wallet.assetPosition(GOOGLE);
        console.log("Despues de __testSetPosition:");
        console.log("  GOOGLE invested (deflado):", newInvested);

        // --- SELLTOKEN (debería trigger take-profit) ---
        uint256 usdtBefore = usdt.balanceOf(address(wallet));

        vm.prank(adgent);
        wallet.selltoken(GOOGLE, "", new StockWallet.V4PoolData[](0));

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        uint256 googleAfter = google.balanceOf(address(wallet));

        console.log("Despues de selltoken (take-profit):");
        console.log("  USDT recibido:", usdtAfter - usdtBefore);
        console.log("  GOOGLE restante:", googleAfter);

        // Verificar: NO vendió todo (take-profit vende solo la ganancia)
        assertGt(googleAfter, 0, "Take-profit should NOT sell all tokens");

        // Verificar: recibió USDT
        assertGt(
            usdtAfter - usdtBefore,
            0,
            "Should receive USDT from take-profit"
        );

        console.log("=== TAKE-PROFIT OK ===");
    }*/

    // =============================================================
    // === TEST 3: NO TRIGGER — el precio está en rango ===
    // =============================================================

    /**
     * @notice Test no trigger: el precio está entre stop-loss y take-profit.
     *         selltoken() debería revertea con TokenNotReadytoSell.
     *
     *         Flujo:
     *         1. Deploy + fund con 1000 USDT
     *         2. invest() — compra GOOGLE
     *         3. __testSetPosition() — setea invested = amount (precio neutro)
     *         4. selltoken(GOOGLE) — debería revertea
     */
    /* function test_selltoken_noTrigger() public {
        console.log("=== TEST: selltoken NO TRIGGER ===");

        wallet = _deployWallet();
        _fundWallet(1000 * 1e18);

        // --- INVEST ---
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 googleBalance = google.balanceOf(address(wallet));
        (uint256 posAmount, uint256 posInvested) = wallet.assetPosition(GOOGLE);

        // --- SIMULAR PRECIO EN RANGO (entre SL y TP) ---
        // SL = 9000 bps (90% del invested) → precio debe ser > 90%
        // TP = 12000 bps (120% del invested) → precio debe ser < 120%
        // Seteamos invested = posInvested real (sin modificar) → precio = 100%
        // Esto está entre 90% y 120% → no trigger
        vm.prank(address(this));
        wallet.__testSetPosition(GOOGLE, posAmount, posInvested);

        // --- SELLTOKEN (debería revertea con TokenNotReadytoSell) ---
        vm.expectRevert(StockWallet.TokenNotReadytoSell.selector);
        vm.prank(adgent);
        wallet.selltoken(GOOGLE, "", new StockWallet.V4PoolData[](0));

        console.log("=== NO TRIGGER OK (reverted correctly) ===");
    }*/

    // =============================================================
    // === TEST 4: PAUSE bloquea selltoken ===
    // =============================================================

    /**
     * @notice Test pause: cuando el contrato está pausado, selltoken()
     *         debería revertea con EnforcedPause.
     */
    /* function test_selltoken_paused() public {
        console.log("=== TEST: selltoken PAUSED ===");

        wallet = _deployWallet();
        _fundWallet(1000 * 1e18);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // Pausar el contrato
        vm.prank(owner);
        wallet.pause();

        // selltoken debería revertea
        vm.expectRevert(StockWallet.EnforcedPause.selector);
        vm.prank(adgent);
        wallet.selltoken(GOOGLE, "", new StockWallet.V4PoolData[](0));

        console.log("=== PAUSED OK (reverted correctly) ===");
    }*/

    // =============================================================
    // === TEST 5: TRADING PAUSE bloquea selltoken pero permite withdraw ===
    // =============================================================

    /**
     * @notice Test tradingPause: cuando el trading está pausado,
     *         selltoken() revertea pero withdrawAsset() funciona.
     */
    /*function test_selltoken_tradingPaused() public {
        console.log("=== TEST: selltoken TRADING PAUSED ===");

        wallet = _deployWallet();
        _fundWallet(1000 * 1e18);

        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // Pausar solo trading
        vm.prank(owner);
        wallet.pauseTrading();

        // selltoken debería revertea
        vm.expectRevert(StockWallet.EnforcedTradingPause.selector);
        vm.prank(adgent);
        wallet.selltoken(GOOGLE, "", new StockWallet.V4PoolData[](0));

        // Pero withdraw sí funciona — usar withdrawAsset para retirar tokens directamente
        uint256 googleBalance = google.balanceOf(address(wallet));
        if (googleBalance > 0) {
            vm.prank(owner);
            wallet.withdrawAsset(GOOGLE);
            assertEq(
                google.balanceOf(owner),
                googleBalance,
                "Withdraw should work when trading paused"
            );
        }

        console.log("=== TRADING PAUSED OK ===");
    }*/
}

// ============
//  INTERFACES
// ============
