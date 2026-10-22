//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, stdMath} from "../lib/forge-std/src/Test.sol";
import {StockWallet} from "../src/StockWallet.sol";
//import {DeployContract} from "../script/aurDeploy.s.sol";
import {IERC20} from "./IERC20.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {
    WETH,
    WBTC,
    USDT,
    XAUt0,
    PLAST,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER
} from "./ConstantsCelo.sol";
contract StockWalletTest is Test {
    StockWallet public wallet;
    address public owner = makeAddr("owner");
    address public adgent = makeAddr("adgent");
    address public adgentContract = makeAddr("adgentContract");

    IERC20 private usdt = IERC20(USDT);
    IERC20 private weth = IERC20(WETH);
    IERC20 private wbtc = IERC20(WBTC);
    IERC20 private xaut0 = IERC20(XAUt0);
    IERC20 private plast = IERC20(PLAST);
    function setUp() public {}
    function test_constructor_checks() public {
        //Test address 0
        StockWallet.AssetConfig memory configx1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });
        StockWallet.AssetConfig memory configx2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.tokenAllocationConfig memory tokenConfigx1 = StockWallet
            .tokenAllocationConfig({token: WBTC, configs: configx1});
        StockWallet.tokenAllocationConfig memory tokenConfigx2 = StockWallet
            .tokenAllocationConfig({token: WETH, configs: configx2});
        // 2. Crear un array en memory con tamaño explícito (1 en este caso)
        StockWallet.tokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.tokenAllocationConfig[](2);

        // 3. Asignar por índice
        tokenAllocation[0] = tokenConfigx1;
        tokenAllocation[1] = tokenConfigx2;
        vm.prank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNISWAP_V3_QUOTER,
            address(adgent),
            address(adgentContract),
            2000,
            tokenAllocation
        );

        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        // --- INICIO ---
        uint256 usdcBalanceBefore = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceBefore = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceBefore = weth.balanceOf(address(wallet));
        console.log("=== BALANCES ANTES ===");
        console.log("USDT Before:", usdcBalanceBefore);
        console.log("WBTC Before:", wbtcBalanceBefore);
        console.log("WETH Before: ", wethBalanceBefore);
        bytes memory pathwbtc = abi.encodePacked(USDT, uint24(3000), WBTC);
        bytes[] memory path = new bytes[](0);
        //path[0] = pathwbtc;
        vm.prank(adgent);

        wallet.invest(path);
        // Balances después
        uint256 usdcBalanceAfter = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceAfter = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceAfter = weth.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES ===");
        console.log("USDC After: ", usdcBalanceAfter);
        console.log("WBTC After: ", wbtcBalanceAfter);
        console.log("WETH After:  ", wethBalanceAfter);

        deal(USDT, address(this), 100 * 1e6);
        usdt.transfer(address(wallet), 100 * 1e6);

        // Agregar nuevos assets
        //need to add config
        vm.prank(owner);

        wallet.addAsset(XAUt0, 2000, address(0));
        vm.prank(owner);

        wallet.addAsset(PLAST, 1000, WETH);

        // Balances de los nuevos tokens ANTES de ejecutar el segundo invest
        uint256 xaut0BalanceBefore = xaut0.balanceOf(address(wallet));
        uint256 plastBalanceBefore = plast.balanceOf(address(wallet));

        console.log("=== BALANCES NUEVOS TOKENS ANTES ===");
        console.log("XAUt0 Before:", xaut0BalanceBefore);
        console.log("PLAST Before: ", plastBalanceBefore);

        // Ejecutamos la inversión con los nuevos assets/rutas
        bytes[] memory paths = new bytes[](0);

        /*paths[0] = abi.encodePacked(USDT, uint24(3000), WBTC);

        paths[1] = abi.encodePacked(
            USDT,
            uint24(3000),
            WETH,
            uint24(3000),
            XAUt0
        );

        paths[2] = abi.encodePacked(
            USDT,
            uint24(3000),
            WETH,
            uint24(3000),
            PLAST
        );*/
        vm.prank(adgent);

        wallet.invest(paths);

        // Balances DESPUÉS
        uint256 usdtBalanceFinal = usdt.balanceOf(address(wallet));
        uint256 wbtcBalanceFinal = wbtc.balanceOf(address(wallet));
        uint256 wethBalanceFinal = weth.balanceOf(address(wallet));
        uint256 xaut0BalanceFinal = xaut0.balanceOf(address(wallet));
        uint256 plastBalanceFinal = plast.balanceOf(address(wallet));

        console.log("=== BALANCES FINALES GENERALES ===");
        console.log("USDT Final: ", usdtBalanceFinal);
        console.log("WBTC Final: ", wbtcBalanceFinal);
        console.log("WETH Final: ", wethBalanceFinal);
        console.log("XAUt0 Final:", xaut0BalanceFinal);
        console.log("PLAST Final:", plastBalanceFinal);

        vm.prank(owner);
        wallet.selltokenAll(paths);
        uint256 usdtBalanceAfterSell = usdt.balanceOf(address(wallet));
        vm.prank(owner);
        wallet.withdrawAssetUsdt(usdtBalanceAfterSell);
    }

    function test_constructor_checks_x2() public {
        // 1. Configuración de los activos
        StockWallet.AssetConfig memory config1 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        StockWallet.AssetConfig memory config2 = StockWallet.AssetConfig({
            allocationBps: 5000,
            stopLossBps: 9500,
            takeProfitBps: 11000
        });

        // 2. Asignar los tokens configurados
        StockWallet.tokenAllocationConfig memory tokenConfig1 = StockWallet
            .tokenAllocationConfig({token: WBTC, configs: config1});

        StockWallet.tokenAllocationConfig memory tokenConfig2 = StockWallet
            .tokenAllocationConfig({token: XAUt0, configs: config2});

        StockWallet.tokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.tokenAllocationConfig[](2);

        tokenAllocation[0] = tokenConfig1;
        tokenAllocation[1] = tokenConfig2;

        // 3. Desplegar la wallet usando USDT como token base
        vm.prank(owner);
        wallet = new StockWallet(
            USDT,
            UNISWAP_V3_FACTORY,
            UNISWAP_V3_QUOTER,
            address(adgent),
            address(adgentContract),
            2000,
            tokenAllocation
        );

        // 4. Financiar la wallet con 10 USDT
        deal(USDT, address(this), 10 * 1e6);
        usdt.transfer(address(wallet), 10 * 1e6);

        // 5. Variables para consultar balances
        uint256 usdtBefore = usdt.balanceOf(address(wallet));
        uint256 wbtcBefore = wbtc.balanceOf(address(wallet));
        uint256 xaut0Before = xaut0.balanceOf(address(wallet));

        console.log("=== BALANCES ANTES ===");
        console.log("USDT:", usdtBefore);
        console.log("WBTC:", wbtcBefore);
        console.log("XAUt0:", xaut0Before);

        // 6. Invertir
        bytes[] memory instructions = new bytes[](0);
        vm.prank(adgent);

        wallet.invest(instructions);

        uint256 usdtAfter = usdt.balanceOf(address(wallet));
        uint256 wbtcAfter = wbtc.balanceOf(address(wallet));
        uint256 xaut0After = xaut0.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES DE INVEST ===");
        console.log("USDT:", usdtAfter);
        console.log("WBTC:", wbtcAfter);
        console.log("XAUt0:", xaut0After);

        // 7. Consultar precio de XAUt0 frente a USDT.
        // Ajusta la cantidad de entrada a los decimales esperados
        // por la implementación de getTwapPrice().
        //console.log("PRECIO XAUt0/USDT:", wallet._getQuote(XAUt0, USDT, 1e18));

        // 8. Modificar posición y vender XAUt0.
        // Verifica que 8e6 sea la unidad que espera modifyPosition().
        wallet.modifyPosition(1e6, XAUt0);

        bytes memory path;
        vm.prank(owner);

        wallet.selltoken(XAUt0, path);

        uint256 xaut0AfterSell = xaut0.balanceOf(address(wallet));
        uint256 usdtAfterSell = usdt.balanceOf(address(wallet));

        console.log("=== BALANCES DESPUES DE SELL ===");
        console.log("XAUt0:", xaut0AfterSell);
        console.log("USDT:", usdtAfterSell);
    }
}
