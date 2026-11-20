//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {StockWallet} from "../src/StockWallet.sol";
import {console2} from "forge-std/console2.sol";
import {
    BTCB,
    ETH,
    USDT,
    ZEC,
    NEAR,
    FXLon,
    WBNB,
    UNISWAP_V3_FACTORY,
    UNISWAP_V3_QUOTER,
    UNISWAP_V4_QUOTER,
    UNIVERSAL_ROUTER,
    PERMIT2,
    V4_POOL_SCANNER
} from "../test/ConstantsBnb.sol";

/// @title StockWalletDeployBnb - Deploy en BNB Chain mainnet
/// @notice Configuracion: 5 assets (ZEC, ETH, BTCB, NEAR, FXLon) sin GOOGLE
///         V3 para crypto + FXLon, V4 con scanner ya deployado
contract deployStockWalletBnbScript is Script {
    // --- V4 Infrastructure on BSC ---
    address constant POOL_MANAGER = 0x28e2Ea090877bF75740558f6BFB36A5ffeE9e9dF;

    // --- Scanner ya deployado en BSC ---
    // Deployed at block 134522506
    // 0xB442ce9A9f3480a7Cad578296917649d9a451cc7

    // --- Adgent addresses ---
    // CAMBIAR ANTES DE DEPLOYAR
    address constant ADGENT = 0xf43ea1700E117e9c456690514Db9C5b1405EC5E5;
    address constant ADGENT_CONTRACT =
        0xf43ea1700E117e9c456690514Db9C5b1405EC5E5;

    // --- Adgent percentage (0%) ---
    uint256 constant ADGENT_PERCENTAGE = 0;

    function run() external {
        deployStockWalletBnb();
    }

    function setConfig(
        uint256 allocationBps,
        uint16 stopLossBps,
        uint16 takeProfitBps,
        address token
    )
        public
        pure
        returns (StockWallet.TokenAllocationConfig memory tokenAllocation)
    {
        StockWallet.AssetConfig memory config = StockWallet.AssetConfig({
            allocationBps: allocationBps,
            stopLossBps: stopLossBps,
            takeProfitBps: takeProfitBps
        });

        return
            StockWallet.TokenAllocationConfig({token: token, configs: config});
    }

    function deployStockWalletBnb() public returns (StockWallet) {
        // ============================================================
        // PORTFOLIO: 5 assets (sin GOOGLE)
        // Allocation recalculado para sumar 100% sin el 5% de GOOGLE
        // ============================================================
        //
        // Original del test (con GOOGLE):
        //   ZEC 30%, ETH 10%, BTCB 10%, NEAR 20%, FXLon 25%, GOOGLE 5%
        //
        // Sin GOOGLE (5 assets):
        //   ZEC 30%, ETH 12%, BTCB 10%, NEAR 20%, FXLon 28% = 100%
        //
        // (Distribui el 5% de GOOGLE entre ETH +2% y FXLon +3%
        //  para mantener proporciones similares)
        // ============================================================

        StockWallet.TokenAllocationConfig[]
            memory tokenAllocation = new StockWallet.TokenAllocationConfig[](5);

        // ZEC - 30% | SL: 95% | TP: 120%
        tokenAllocation[0] = setConfig(3000, 9500, 12000, ZEC);

        // ETH - 12% | SL: 90% | TP: 120%
        tokenAllocation[1] = setConfig(1200, 9000, 12000, ETH);

        // BTCB - 10% | SL: 90% | TP: 120%
        tokenAllocation[2] = setConfig(1000, 9000, 12000, BTCB);

        // NEAR - 20% | SL: 90% | TP: 120%
        tokenAllocation[3] = setConfig(2000, 9000, 12000, NEAR);

        // FXLon - 28% | SL: 90% | TP: 120%
        tokenAllocation[4] = setConfig(2800, 9000, 12000, FXLon);

        // Verificar suma = 10000 (100%)
        uint256 totalAlloc = 0;
        for (uint256 i = 0; i < tokenAllocation.length; i++) {
            totalAlloc += tokenAllocation[i].configs.allocationBps;
        }
        require(totalAlloc == 10000, "Allocation must equal 100%");

        address sender = msg.sender;
        console2.log("=== StockWallet Deploy BNB Chain ===");
        console2.log("Sender (owner): %s", sender);
        console2.log("Adgent: %s", ADGENT);
        console2.log("Adgent Contract: %s", ADGENT_CONTRACT);
        console2.log("V4 PoolScanner (existing): %s", V4_POOL_SCANNER);
        console2.log("Total allocation: %s", totalAlloc);

        vm.startBroadcast(sender);

        // 1. Deploy StockWallet usando el scanner ya deployado
        StockWallet stockWallet = new StockWallet(
            USDT, // _usdc (base token = USDT en BSC)
            UNISWAP_V3_FACTORY, // _factory
            UNIVERSAL_ROUTER, // _universal_router
            PERMIT2, // _permit2
            UNISWAP_V3_QUOTER, // _quoter
            UNISWAP_V4_QUOTER, // _quoterV4
            POOL_MANAGER, // _poolManager
            V4_POOL_SCANNER, // _v4Scanner (ya deployado)
            ADGENT, // _adgent
            ADGENT_CONTRACT, // _adgentContract
            ADGENT_PERCENTAGE, // _adgentPercentage (0%)
            tokenAllocation
        );
        console2.log("StockWallet deployed: %s", address(stockWallet));

        // 2. Set gas token = WBNB (gas fee se paga en WBNB)
        stockWallet.setGasToken(WBNB);
        console2.log("GasToken set to WBNB: %s", WBNB);

        vm.stopBroadcast();

        console2.log("=== Deploy completo ===");
        console2.log("StockWallet: %s", address(stockWallet));
        console2.log("PoolScanner (existing): %s", V4_POOL_SCANNER);
        console2.log("Owner: %s", sender);
        console2.log("Adgent: %s", ADGENT);
        console2.log("GasToken: %s (WBNB)", WBNB);

        return stockWallet;
    }
}
