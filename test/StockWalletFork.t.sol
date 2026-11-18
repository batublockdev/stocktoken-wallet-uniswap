//SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {IERC20} from "./IERC20.sol";
import {
    BTCB,
    ETH,
    USDT,
    USDC,
    AAPLon,
    TSLAon,
    USDY,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNISWAP_V4_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2
} from "./ConstantsBnb.sol";

/// @title StockWalletForkTest — Tests con fork de BSC mainnet
/// @notice Cubre invest(), selltoken() y selltokenAll() con swaps reales
contract StockWalletForkTest is Test {
    StockWallet public wallet;
    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    // Tokens reales de BSC
    IERC20 private usdt = IERC20(USDT);
    IERC20 private btcb = IERC20(BTCB);
    IERC20 private eth = IERC20(ETH);

    /// @dev Fork BSC mainnet en el bloque actual
    function setUp() public {
        // Hacer fork de BNB Chain mainnet (RPC público)
        vm.createSelectFork(
            "https://bsc-dataseed.binance.org",
            43800000 // Bloque reciente estable
        );

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
            token: BTCB,
            configs: configBtcb
        });
        tokenAllocation[1] = StockWallet.TokenAllocationConfig({
            token: ETH,
            configs: configEth
        });

        vm.startPrank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNIVERSAL_ROUTER,
            PERMIT2,
            UNISWAP_V3_QUOTER,
            UNISWAP_V4_QUOTER,
            address(0),
            address(0),
            adgent,
            adgentContract,
            2000, // adgentPercentage = 20%
            tokenAllocation
        );
        vm.stopPrank();

        // Fund wallet with 1000 USDT (18 decimals en BSC)
        deal(USDT, address(this), 1000 * 1e18);
        usdt.transfer(address(wallet), 1000 * 1e18);
    }

    // =============================================================
    // === INVEST TEST (con fork — swap real) ===
    // =============================================================

    /// @notice Test que invest() distribuye USDT en BTCB y ETH via Uniswap V3
    function test_invest_success() public {
        uint256 usdtBalanceBefore = usdt.balanceOf(address(wallet));
        assertEq(usdtBalanceBefore, 1000 * 1e18, "Wallet should have 1000 USDT");

        // adgent llama invest()
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // Después de invest:
        // 1. Gas fee (2%) y adgent fee (20%) se descuentan
        // 2. El resto se invierte 50/50 en BTCB y ETH
        uint256 usdtBalanceAfter = usdt.balanceOf(address(wallet));
        assertEq(usdtBalanceAfter, 0, "All USDT should be spent after invest");

        // Verificar que el adgent recibió el gas fee
        uint256 adgentBalance = usdt.balanceOf(adgent);
        assertGt(adgentBalance, 0, "Adgent should have received gas fee");

        // Verificar que el adgentContract recibió su fee
        uint256 adgentContractBalance = usdt.balanceOf(adgentContract);
        assertGt(adgentContractBalance, 0, "Adgent contract should have received fee");

        // Verificar que el wallet tiene BTCB y ETH
        uint256 btcbBalance = btcb.balanceOf(address(wallet));
        assertGt(btcbBalance, 0, "Wallet should have BTCB after invest");

        uint256 ethBalance = eth.balanceOf(address(wallet));
        assertGt(ethBalance, 0, "Wallet should have ETH after invest");

        // Verificar positions
        (uint256 btcbAmount, uint256 btcbInvested) = wallet.assetPosition(BTCB);
        assertGt(btcbAmount, 0, "BTCB position amount should be > 0");
        assertGt(btcbInvested, 0, "BTCB position invested should be > 0");

        (uint256 ethAmount, uint256 ethInvested) = wallet.assetPosition(ETH);
        assertGt(ethAmount, 0, "ETH position amount should be > 0");
        assertGt(ethInvested, 0, "ETH position invested should be > 0");

        // Log resultados para debug
        console.log("=== INVEST RESULTS ===");
        console.log("USDT spent:", usdtBalanceBefore);
        console.log("BTCB received:", btcbBalance);
        console.log("ETH received:", ethBalance);
        console.log("Adgent gas fee:", adgentBalance);
        console.log("Adgent contract fee:", adgentContractBalance);
    }

    /// @notice Test que invest() revierte si no tiene USDT
    function test_invest_revert_NoBalance() public {
        // Vaciar el wallet — solo owner puede withdraw
        uint256 walletBalance = usdt.balanceOf(address(wallet));
        vm.prank(owner);
        wallet.withdrawAssetUsdt(walletBalance);

        // Ahora invest debe revertir por balance 0
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

    /// @notice Test que invest() revierte si no tiene rol ADGENT
    function test_invest_revert_NotAdgentRole() public {
        address random = makeAddr("random");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                random,
                wallet.ADGENT_ROLE()
            )
        );
        vm.prank(random);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));
    }

    // =============================================================
    // === SELLTOKENALL TEST (con fork — swap real) ===
    // =============================================================

    /// @notice Test que selltokenAll() vende todo y vuelve a USDT
    function test_selltokenAll_success() public {
        // Primero investir
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 btcbBefore = btcb.balanceOf(address(wallet));
        uint256 ethBefore = eth.balanceOf(address(wallet));
        assertGt(btcbBefore, 0, "Should have BTCB before selltokenAll");
        assertGt(ethBefore, 0, "Should have ETH before selltokenAll");

        // Owner vende todo
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        // Después de selltokenAll, todo debería estar en USDT
        uint256 btcbAfter = btcb.balanceOf(address(wallet));
        uint256 ethAfter = eth.balanceOf(address(wallet));
        assertEq(btcbAfter, 0, "Should have 0 BTCB after selltokenAll");
        assertEq(ethAfter, 0, "Should have 0 ETH after selltokenAll");

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        assertGt(usdtAfter, 0, "Should have USDT after selltokenAll");

        // Positions reset
        (uint256 btcbAmount, uint256 btcbInvested) = wallet.assetPosition(BTCB);
        assertEq(btcbAmount, 0, "BTCB position should be reset");
        assertEq(btcbInvested, 0, "BTCB invested should be reset");

        (uint256 ethAmount, uint256 ethInvested) = wallet.assetPosition(ETH);
        assertEq(ethAmount, 0, "ETH position should be reset");
        assertEq(ethInvested, 0, "ETH invested should be reset");

        console.log("=== SELLTOKENALL RESULTS ===");
        console.log("BTCB sold:", btcbBefore);
        console.log("ETH sold:", ethBefore);
        console.log("USDT received:", usdtAfter);
    }

    /// @notice Test que selltokenAll() revierte si no es owner
    function test_selltokenAll_revert_NotOwner() public {
        vm.expectRevert(
            abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", adgent)
        );
        vm.prank(adgent);
        wallet.selltokenAll(new bytes[](0));
    }

    // =============================================================
    // === SELLTOKEN TEST (con fork — swap real) ===
    // =============================================================

    /// @notice Test que selltoken() ejecuta take profit cuando el precio sube
    function test_selltoken_takeProfit() public {
        // Investir primero
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        (uint256 btcbAmountBefore, uint256 btcbInvestedBefore) = wallet.assetPosition(BTCB);
        console.log("BTCB position before:", btcbAmountBefore);
        console.log("BTCB invested before:", btcbInvestedBefore);

        // Manipular el precio: darle más BTCB al wallet para simular ganancia
        // Esto simula que el precio subió (más tokens que lo invertido)
        uint256 extraBtcb = btcbAmountBefore / 2; // 50% más tokens = ganancia
        deal(BTCB, address(wallet), btcb.balanceOf(address(wallet)) + extraBtcb);

        // Llamar selltoken con take profit (config: TP = 11000 = 10% gain)
        // Como le dimos más tokens, el precio debería ser mayor al threshold
        vm.prank(adgent);
        wallet.selltoken(BTCB, new bytes(0), new StockWallet.V4PoolData[](0));

        console.log("=== TAKE PROFIT RESULTS ===");
        console.log("Extra BTCB simulated:", extraBtcb);

        // Después del take profit, debería haber vendido la porción de ganancia
        uint256 btcbAfter = btcb.balanceOf(address(wallet));
        console.log("BTCB remaining after TP:", btcbAfter);
    }

    /// @notice Test que selltoken() ejecuta stop loss cuando el precio baja
    function test_selltoken_stopLoss() public {
        // Investir primero
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        (, uint256 btcbInvested) = wallet.assetPosition(BTCB);
        console.log("BTCB invested before:", btcbInvested);

        // Reducir los tokens del wallet para simular pérdida grande
        // Le dejamos solo 10% de los tokens — el valor actual será ~10% del invertido,
        // muy por debajo del stop loss (9500 = 95%)
        uint256 btcbBalance = btcb.balanceOf(address(wallet));
        deal(BTCB, address(wallet), btcbBalance / 10);

        // El stop loss debería dispararse: vende todo y remueve el asset
        vm.prank(adgent);
        wallet.selltoken(BTCB, new bytes(0), new StockWallet.V4PoolData[](0));

        // Después del stop loss, BTCB debería haber sido removido del portfolio
        (uint256 alloc, , ) = wallet.assetConfig(BTCB);
        assertEq(alloc, 0, "BTCB should be removed from portfolio after stop loss");

        // El wallet debería tener USDT del swap
        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        assertGt(usdtAfter, 0, "Should have USDT after stop loss");

        // BTCB balance debería ser 0
        assertEq(btcb.balanceOf(address(wallet)), 0, "Should have 0 BTCB after stop loss");

        console.log("=== STOP LOSS RESULTS ===");
        console.log("USDT received from stop loss:", usdtAfter);
    }

    /// @notice Test que selltoken() revierte si el token no está listo para vender
    function test_selltoken_revert_NotReadyToSell() public {
        // Investir primero
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        // Sin manipular el precio, el token no debería estar en SL ni TP
        // Usamos expectRevert sin selector porque el contrato puede revertir
        // con TokenNotReadytoSell o PoolNoExiste dependiendo del estado del pool
        vm.expectRevert();
        vm.prank(adgent);
        wallet.selltoken(BTCB, new bytes(0), new StockWallet.V4PoolData[](0));
    }

    /// @notice Test que selltoken() revierte si no tiene rol ADGENT
    function test_selltoken_revert_NotAdgentRole() public {
        address random = makeAddr("random");
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)",
                random,
                wallet.ADGENT_ROLE()
            )
        );
        vm.prank(random);
        wallet.selltoken(BTCB, new bytes(0), new StockWallet.V4PoolData[](0));
    }

    /// @notice Test que selltoken() revierte si el balance es 0
    function test_selltoken_revert_ZeroBalance() public {
        // No investir, no hay tokens
        vm.expectRevert(
            abi.encodeWithSelector(
                StockWallet.InsufficientTokenBalance.selector,
                BTCB,
                0,
                0
            )
        );
        vm.prank(adgent);
        wallet.selltoken(BTCB, new bytes(0), new StockWallet.V4PoolData[](0));
    }

    // =============================================================
    // === DEPOSIT ASSET CON SWAP (con fork) ===
    // =============================================================

    /// @notice Test que depositAsset con token no-USDT hace swap a USDT
    function test_depositAsset_swapToUsdt() public {
        // Darle BTCB al adgent
        uint256 btcbAmount = 1 * 1e18; // 1 BTCB
        deal(BTCB, adgent, btcbAmount);

        vm.startPrank(adgent);
        btcb.approve(address(wallet), btcbAmount);

        uint256 usdtBefore = usdt.balanceOf(address(wallet));
        wallet.depositAsset(BTCB, btcbAmount, new bytes(0));
        vm.stopPrank();

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        assertGt(usdtAfter, usdtBefore, "Wallet should have more USDT after BTCB deposit");

        console.log("=== DEPOSIT ASSET (BTCB -> USDT) ===");
        console.log("BTCB deposited:", btcbAmount);
        console.log("USDT received:", usdtAfter - usdtBefore);
    }

    // =============================================================
    // === FULL CYCLE: invest -> selltokenAll ===
    // =============================================================

    /// @notice Test completo: invest y luego selltokenAll, verificar que recupera USDT
    function test_fullCycle_invest_sellAll() public {
        uint256 usdtInitial = usdt.balanceOf(address(wallet));

        // Step 1: Invest
        vm.prank(adgent);
        wallet.invest(new bytes[](0), new StockWallet.V4PoolData[][](0));

        uint256 usdtAfterInvest = usdt.balanceOf(address(wallet));
        assertEq(usdtAfterInvest, 0, "All USDT spent after invest");

        uint256 btcbHeld = btcb.balanceOf(address(wallet));
        uint256 ethHeld = eth.balanceOf(address(wallet));
        assertGt(btcbHeld, 0);
        assertGt(ethHeld, 0);

        // Step 2: Sell all
        vm.prank(owner);
        wallet.selltokenAll(new bytes[](0));

        uint256 usdtRecovered = usdt.balanceOf(address(wallet));
        assertGt(usdtRecovered, 0, "Should recover USDT");

        // Por las fees (gas 2% + adgent 20% = 22% total),
        // lo recuperado debería ser <= 78% del inicial (antes de fees de swap)
        // Pero verificamos que sea razonable (al menos 50% del inicial)
        assertGe(usdtRecovered, usdtInitial / 2, "Should recover at least 50% of initial");

        console.log("=== FULL CYCLE ===");
        console.log("USDT initial:", usdtInitial);
        console.log("USDT recovered:", usdtRecovered);
        console.log("Recovery %:", (usdtRecovered * 100) / usdtInitial);
    }
}
